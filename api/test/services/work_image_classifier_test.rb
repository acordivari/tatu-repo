require "test_helper"

# The classifier must never turn an unusable response into a confident verdict:
# a bogus "person" hides real work, which is worse than leaving it unclassified.
class WorkImageClassifierTest < ActiveSupport::TestCase
  def parse(text)
    WorkImageClassifier.allocate.send(:parse, text)
  end

  test "parses a well-formed verdict" do
    v = parse('{"kind": "person", "confidence": 0.82}')

    assert_equal "person", v.kind
    assert_in_delta 0.82, v.confidence
    assert_not v.work?
  end

  test "tolerates prose around the JSON" do
    assert_equal "work", parse('Here you go: {"kind":"work","confidence":0.9} ').kind
  end

  test "returns nil for an unknown kind rather than guessing" do
    assert_nil parse('{"kind": "tattoo", "confidence": 0.9}')
  end

  test "returns nil for unparseable output" do
    assert_nil parse("I cannot tell what this is")
    assert_nil parse('{"kind": broken')
  end

  test "version is recorded so a prompt change can invalidate past verdicts" do
    assert WorkImageClassifier::VERSION.present?
  end
end
