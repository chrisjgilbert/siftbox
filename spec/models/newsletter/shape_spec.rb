require "rails_helper"

RSpec.describe Newsletter::Shape do
  def shape_of(html)
    Newsletter::Shape.new(Newsletter::Body.new(html))
  end

  def two_column_grid
    %(<table><tr>) +
      %(<td><img src="https://cdn.example/one.png"><p>Story one</p></td>) +
      %(<td><img src="https://cdn.example/two.png"><p>Story two</p></td>) +
      %(</tr></table>)
  end

  it "reads prose as prose" do
    html = "<h2>The obvious wins</h2><p>Bootsnap is doing more than you think.</p>"

    expect(shape_of(html)).not_to be_designed
  end

  it "reads an empty body as prose" do
    expect(shape_of("")).not_to be_designed
  end

  # The signal a two-column story grid gives off, and the one that costs the
  # reader most: collapsing it to a single column shuffles every image away
  # from the headline it belongs to.
  it "reads a row carrying more than one filled cell as designed" do
    expect(shape_of(two_column_grid)).to be_designed
  end

  # A single table holding a run of blocks is a newsletter written as a list,
  # which reads correctly once the cells stack.
  it "reads one table of single-cell rows as prose" do
    html = %(<table>) +
      %(<tr><td><p>First story</p></td></tr>) +
      %(<tr><td><p>Second story</p></td></tr>) +
      %(</table>)

    expect(shape_of(html)).not_to be_designed
  end

  # Nesting is how an ESP builds a fixed-width canvas: an outer table for the
  # page background, an inner one for the 600px column, more inside that. One
  # table is a list; three is a layout.
  it "reads nested layout tables as designed" do
    html = %(<table><tr><td><table><tr><td><table><tr><td>) +
      %(<p>Deep inside a layout</p>) +
      %(</td></tr></table></td></tr></table></td></tr></table>)

    expect(shape_of(html)).to be_designed
  end

  it "reads two levels of table as prose" do
    html = %(<table><tr><td><table><tr><td><p>A quoted table</p></td></tr></table></td></tr></table>)

    expect(shape_of(html)).not_to be_designed
  end

  # Spacer cells are how a fixed-width canvas pads its edges. Counting them
  # as content would read every padded single column as a grid.
  it "does not count a row's empty cells towards the grid" do
    html = %(<table><tr><td></td><td><p>The only content</p></td><td></td></tr></table>)

    expect(shape_of(html)).not_to be_designed
  end

  it "counts a cell holding only an image as filled" do
    html = %(<table><tr>) +
      %(<td><img src="https://cdn.example/one.png"></td>) +
      %(<td><img src="https://cdn.example/two.png"></td>) +
      %(</tr></table>)

    expect(shape_of(html)).to be_designed
  end

  # Reads the scrubbed document, so a tracking beacon in a cell of its own
  # cannot make a single column look like a grid.
  it "does not let a tracking pixel fill a cell" do
    html = %(<table><tr>) +
      %(<td><img src="https://track.example/o.gif" width="1" height="1"></td>) +
      %(<td><p>The only content</p></td>) +
      %(</tr></table>)

    expect(shape_of(html)).not_to be_designed
  end
end
