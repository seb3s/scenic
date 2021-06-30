#
#  Created by Boyd Multerer on 2021-05-25.
#  Copyright © 2017-2021 Kry10 Limited. All rights reserved.
#

defmodule Scenic.Primitive.Style.LineHeight do
  @moduledoc """

  Adjust the vertical spacing of lines of text in a single block. This is expressed as a percentage
  of the size of the font. So setting a value of `1.2` would mean 120% the font size as the spacing
  from baseline to baseline.

  The default if `:line_height` is not specified is `1.2`

  Example:

      graph
      |> text("Some Text\\r\\nMore Text", line_height: 1.1)

  The natural vertical spacing of the font is used by default. Set this style if
  you want to override it.


  ## Note

  This style is not actually represented in the low-level script format. Instead it is
  a hint that is processed when a graph is "compiled" in a script. Essentially it instructs
  the graph compiler to automatically apply transforms to each line in a multi-line text
  string that separate out the lines of text from each other.
  """

  use Scenic.Primitive.Style

  # ============================================================================
  # data verification and serialization

  def validate( size ) when is_number(size), do: {:ok, size}
  def validate( data )  do
    {
      :error,
      """
      #{IO.ANSI.red()}Invalid LineHeight specification
      Received: #{inspect(data)}
      #{IO.ANSI.yellow()}
      The :line_height style must be a positive number#{IO.ANSI.default_color()}
      """
    }
  end

end
