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
    assert_equal "tattoo", parse('Here you go: {"kind":"tattoo","confidence":0.9} ').kind
  end

  test "returns nil for an unknown kind rather than guessing" do
    assert_nil parse('{"kind": "flash", "confidence": 0.9}')
    # v5 dropped "work" from the prompt; a reply using it is stale, not a verdict.
    assert_nil parse('{"kind": "work", "confidence": 0.9}')
  end

  test "returns nil for unparseable output" do
    assert_nil parse("I cannot tell what this is")
    assert_nil parse('{"kind": broken')
  end

  test "version is recorded so a prompt change can invalidate past verdicts" do
    assert WorkImageClassifier::VERSION.present?
  end

  test "prompt carries OCR text only when there is some" do
    assert_equal WorkImageClassifier::INSTRUCTIONS, WorkImageClassifier.prompt(nil)
    assert_equal WorkImageClassifier::INSTRUCTIONS, WorkImageClassifier.prompt("  \n ")

    prompt = WorkImageClassifier.prompt("TORONTO\nSUMMER FALL 2026\nBOOKING AVAILABLE")
    assert prompt.start_with?(WorkImageClassifier::INSTRUCTIONS)
    assert_includes prompt, "TORONTO SUMMER FALL 2026 BOOKING AVAILABLE"
  end

  test "prompt truncates long OCR text" do
    prompt = WorkImageClassifier.prompt("word " * 500)
    assert_operator prompt.length, :<, WorkImageClassifier::INSTRUCTIONS.length +
                                       WorkImageClassifier::OCR_CONTEXT.length +
                                       WorkImageClassifier::OCR_MAX_CHARS
  end

  test "tattoo and design both count as work" do
    assert parse('{"kind": "tattoo", "confidence": 0.9}').work?
    assert parse('{"kind": "design", "confidence": 0.9}').work?
    assert_not parse('{"kind": "other", "confidence": 0.9}').work?
  end

  test "prompt carries the caption as medium context only when present" do
    assert_equal WorkImageClassifier::INSTRUCTIONS, WorkImageClassifier.prompt(nil, "  ")

    prompt = WorkImageClassifier.prompt(nil, "Latest painting I've been working on.\n26x31 inches")
    assert_includes prompt, "Latest painting I've been working on. 26x31 inches"
    assert_includes prompt, "do not make the image \"promo\""
  end
end
