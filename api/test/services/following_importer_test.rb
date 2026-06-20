require "test_helper"

# The IG "Download Your Information" export puts the handle in "title" and uses a
# /_u/ redirect prefix in hrefs — a real export once parsed to a single bogus
# "_u" handle before this was fixed. These lock down the shapes.
class FollowingImporterTest < ActiveSupport::TestCase
  def importer = FollowingImporter.new("unused.json")

  test "from_url strips the /_u/ redirect prefix and trailing slashes" do
    assert_equal "coolhandle", importer.send(:from_url, "https://www.instagram.com/_u/coolhandle")
    assert_equal "plainhandle", importer.send(:from_url, "https://instagram.com/plainhandle/")
  end

  test "handle_from prefers the title field" do
    assert_equal ["titlehandle"], importer.send(:handle_from, { "title" => "titlehandle" })
  end

  test "handle_from reads string_list_data value, then href" do
    assert_equal ["valhandle"],
                 importer.send(:handle_from, { "string_list_data" => [{ "value" => "valhandle" }] })
    assert_equal ["hrefhandle"],
                 importer.send(:handle_from, { "string_list_data" => [{ "href" => "https://www.instagram.com/_u/hrefhandle" }] })
  end

  test "handle_from accepts a bare URL string" do
    assert_equal ["strhandle"], importer.send(:handle_from, "https://www.instagram.com/_u/strhandle")
  end

  test "call corroborates known artists and queues unknown ones" do
    Artist.create!(handle: "knownone")
    file = Tempfile.new(["following", ".json"])
    file.write({ "relationships_following" => [
      { "title" => "knownone" },
      { "title" => "strangerone" }
    ] }.to_json)
    file.close

    res = FollowingImporter.new(file.path).call

    assert_equal 2, res.total
    assert_equal 1, res.corroborated
    assert_equal 1, res.queued
    assert_includes Artist.find_by(handle: "knownone").sources, "personal_following"
    assert ArtistCandidate.exists?(handle: "strangerone")
  ensure
    file&.unlink
  end
end
