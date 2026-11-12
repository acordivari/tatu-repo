require "test_helper"

# Every image the site shows is the 640px :card variant. The other tests attach
# a few placeholder bytes and never resize anything, so they keep passing when
# the resize backend is missing or broken — which is exactly what an
# image_processing upgrade did once (2.0 stopped installing mini_magick). These
# run a real JPEG through ImageMagick.
class ImageUrlsTest < ActiveSupport::TestCase
  def setup
    # Public-bucket URLs, as in production: the storage key is in the URL.
    @public_base_was = ENV["R2_PUBLIC_BASE"]
    ENV["R2_PUBLIC_BASE"] = "https://images.example.test"
    @artist = Artist.create!(handle: "variantartist")
    @post = Post.create!(ig_shortcode: "variant_real_jpeg", artist: @artist, posted_at: 1.day.ago)
    @post.image.attach(
      ActiveStorage::Blob.create_and_upload!(
        io: file_fixture("sample_1280x960.jpg").open, filename: "sample.jpg", content_type: "image/jpeg"
      )
    )
  end

  def teardown
    @post.image.purge
    ENV["R2_PUBLIC_BASE"] = @public_base_was
  end

  test "the card variant is resized to fit 640px, keeping the aspect ratio" do
    card = @post.image.variant(:card).processed.image.blob

    assert_equal "image/jpeg", card.content_type
    assert_equal [ 640, 480 ], dimensions_of(card)
    assert_operator card.byte_size, :<, @post.image.blob.byte_size
  end

  test "a post's image URL points at the card variant, not the original" do
    url = ImageUrls.post_image_url(@post)
    card = @post.image.variant(:card).processed.image.blob

    assert_equal "https://images.example.test/#{card.key}", url
    assert_not_equal @post.image.blob.key, card.key
  end

  test "the classifier's downscale shrinks a large image and leaves a small one alone" do
    original = file_fixture("sample_1280x960.jpg").binread
    small = WorkImageClassifier.downscale(original, max_edge: 512)

    assert_equal [ 512, 384 ], dimensions_of_bytes(small)
    assert_equal small, WorkImageClassifier.downscale(small, max_edge: 512)
  end

  private

  def dimensions_of(blob)
    dimensions_of_bytes(blob.download)
  end

  def dimensions_of_bytes(bytes)
    image = MiniMagick::Image.read(bytes)
    [ image.width, image.height ]
  end
end
