# Testing

## Process

- **Write the test first.** Red, green, refactor. Don't write implementation ahead of a failing
  test.
- Test pyramid: many model and PORO unit specs, some request specs, few system specs.
- Every public method on a model or PORO has at least one spec. Every branch of a conditional
  has at least one spec.
- One `it` per path through the method. The description names the condition and the result.

## Structure

- **No `let`, `let!`, or `before`.** Do the setup inside the example, so the reader never has to
  scroll up to find out what an object is.
- No `its`, `specify`, or bare `subject` in an example. No instance variables.
- Four phases separated by blank lines: setup, exercise, verify, teardown.
- Extract a helper method that takes arguments when setup repeats. Don't rebuild `let`.
- Test behaviour, not implementation. Never test private methods. Never stub the object under
  test.

```ruby
# Before
describe Order do
  let(:order) { create(:order, settled_at: nil) }

  it { expect(order).not_to be_settled }
end

# After
describe Order do
  it "is not settled until settled_at is set" do
    order = build_stubbed(:order, settled_at: nil)

    expect(order).not_to be_settled
  end
end
```

## Tools

- `build` or `build_stubbed` unless the test needs persistence.
- Factories carry required attributes only, with sensible defaults. Start in
  `spec/factories.rb`. Date and time attributes go in blocks so they evaluate per build:
  `archived_at { 1.day.ago }`.
- Shoulda Matchers for validations and associations.
- Stubs and spies, not mocks. Never `any_instance_of` — inject the collaborator.
- Assert on state for incoming messages; assert with a spy for outgoing ones.
- `WebMock.disable_net_connect!` blocks real HTTP. Stub every external request. Prefer a fake
  object over stubbing HTTP when the app owns the client. webmock over VCR.
- Never point tests at S3 or another live storage backend.
- `expect` syntax, `allow` for stubs, `not_to` rather than `to_not`, `eq` rather than `==`.
  Predicate matchers rather than comparing to `true`.
- Capybara: find elements by accessible name, label, or role. Not by CSS or `#id`. `have_css`
  over `have_selector` when a selector is unavoidable.
