Prawn::Font::AFM.instance_variable_set :@hide_m17n_warning, true

require 'prawn/icon'

module Asciidoctor
module Prawn
module Extensions
  include ::Prawn::Measurements
  include ::Asciidoctor::Pdf::Sanitizer

  IconSets = ['fa', 'fi', 'octicon', 'pf'].to_set
  MeasurementValueRx = /(\d+|\d*\.\d+)(in|mm|cm|px|pt)?$/
  InitialPageContent = %(q\n)

  # - :height is the height of a line
  # - :leading is spacing between adjacent lines
  # - :padding_top is half line spacing, plus any line_gap in the font
  # - :padding_bottom is half line spacing
  # - :final_gap determines whether a gap is added below the last line
  LineMetrics = ::Struct.new :height, :leading, :padding_top, :padding_bottom, :final_gap

  # Core

  # Retrieves the catalog reference data for the PDF.
  #
  def catalog
    state.store.root
  end

  # Measurements

  # Returns the width of the current page from edge-to-edge
  #
  def page_width
    page.dimensions[2]
  end

  # Returns the effective (writable) width of the page
  #
  # If inside a fixed-height bounding box, returns height of box.
  #
  def effective_page_width
    reference_bounds.width
  end

  # Returns the height of the current page from edge-to-edge
  #
  def page_height
    page.dimensions[3]
  end

  # Returns the effective (writable) height of the page
  #
  # If inside a fixed-height bounding box, returns width of box.
  #
  def effective_page_height
    reference_bounds.height
  end

  # Set the margins for the current page.
  #
  def set_page_margin margin
    # FIXME is there a cleaner way to set margins? does it make sense to override create_new_page?
    apply_margin_options margin: margin
    generate_margin_box
  end

  # Returns the margins for the current page as a 4 element array (top, right, bottom, left)
  #
  def page_margin
    [page.margins[:top], page.margins[:right], page.margins[:bottom], page.margins[:left]]
  end

  # Returns the width of the left margin for the current page
  #
  def page_margin_left
    page.margins[:left]
  end
  # deprecated
  alias :left_margin :page_margin_left

  # Returns the width of the right margin for the current page
  #
  def page_margin_right
    page.margins[:right]
  end
  # deprecated
  alias :right_margin :page_margin_right

  # Returns the width of the top margin for the current page
  #
  def page_margin_top
    page.margins[:top]
  end

  # Returns the width of the bottom margin for the current page
  #
  def page_margin_bottom
    page.margins[:bottom]
  end

  # Returns the total left margin (to the page edge) for the current bounds.
  #
  def bounds_margin_left
    bounds.absolute_left
  end

  # Returns the total right margin (to the page edge) for the current bounds.
  #
  def bounds_margin_right
    page.dimensions[2] - bounds.absolute_right
  end

  # Returns the side the current page is facing, :recto or :verso.
  #
  def page_side pgnum = nil
    (recto_page? pgnum) ? :recto : :verso
  end

  # Returns whether the page is a recto page.
  #
  def recto_page? pgnum = nil
    (pgnum || page_number).odd?
  end

  # Returns whether the page is a verso page.
  #
  def verso_page? pgnum = nil
    (pgnum || page_number).even?
  end

  # Returns whether the cursor is at the top of the page (i.e., margin box).
  #
  def at_page_top?
    @y == @margin_box.absolute_top
  end

  # Returns whether the current page is empty (i.e., no content has been written).
  # Returns false if a page has not yet been created.
  #
  def empty_page?
    # if we are at the page top, assume we didn't write anything to the page
    #at_page_top?
    # ...or use more robust, low-level check (initial value of content is "q\n")
    page_number > 0 && page.content.stream.filtered_stream == InitialPageContent
  end
  alias :page_is_empty? :empty_page?

  # Returns whether the current page is the last page in the document.
  #
  def last_page?
    page_number == page_count
  end

  # Converts the specified float value to a pt value from the
  # specified unit of measurement (e.g., in, cm, mm, etc).
  def to_pt num, units
    if units.nil_or_empty?
      num
    else
      case units
      when 'pt'
        num
      when 'in'
        num * 72
      when 'mm'
        num * (72 / 25.4)
      when 'cm'
        num * (720 / 25.4)
      when 'px'
        num * 0.75
      end
    end
  end

  # Convert the specified string value to a pt value from the
  # specified unit of measurement (e.g., in, cm, mm, etc).
  #
  # Examples:
  #
  #  0.5in => 36.0
  #  100px => 75.0
  #
  def str_to_pt val
    if MeasurementValueRx =~ val
      to_pt $1.to_f, $2
    end
  end

  # Destinations

  # Generates a destination object that resolves to the top of the page
  # specified by the page_num parameter or the current page if no page number
  # is provided. The destination preserves the user's zoom level unlike
  # the destinations generated by the outline builder.
  #
  def dest_top page_num = nil
    dest_xyz 0, page_height, nil, (page_num ? state.pages[page_num - 1] : page)
  end

  # Fonts

  # Registers a new custom font described in the data parameter
  # after converting the font name to a String.
  #
  # Example:
  #
  #  register_font Roboto: {
  #    normal: 'fonts/roboto-normal.ttf',
  #    italic: 'fonts/roboto-italic.ttf',
  #    bold: 'fonts/roboto-bold.ttf',
  #    bold_italic: 'fonts/roboto-bold_italic.ttf'
  #  }
  #  
  def register_font data
    font_families.update data.inject({}) {|accum, (key, val)| accum[key.to_s] = val; accum }
  end

  # Enhances the built-in font method to allow the font
  # size to be specified as the second option and to
  # lazily load font-based icons.
  #
  def font name = nil, options = {}
    if name
      ::Prawn::Icon::FontData.load self, name if IconSets.include? name
      options = { size: options } if ::Numeric === options
    end
    super name, options
  end

  # Retrieves the current font name (i.e., family).
  #
  def font_family
    font.options[:family]
  end

  alias :font_name :font_family

  # Retrieves the current font info (family, style, size) as a Hash
  #
  def font_info
    { family: font.options[:family], style: (font.options[:style] || :normal), size: @font_size }
  end

  # Sets the font style for the scope of the block to which this method
  # yields. If the style is nil and no block is given, return the current 
  # font style.
  #
  def font_style style = nil
    if block_given?
      font font.options[:family], style: style do
        yield
      end
    elsif style
      font font.options[:family], style: style
    else
      font.options[:style] || :normal
    end
  end

  # Applies points as a scale factor of the current font if the value provided
  # is less than or equal to 1 or it's a string (e.g., 1.1em), then delegates to the super
  # implementation to carry out the built-in functionality.
  #
  #--
  # QUESTION should we round the result?
  def font_size points = nil
    return @font_size unless points
    if points == 1
      super @font_size
    elsif String === points
      if points.end_with? 'rem'
        super (@theme.base_font_size * points.to_f)
      elsif points.end_with? 'em'
        super (@font_size * points.to_f)
      elsif points.end_with? '%'
        super (@font_size * (points.to_f / 100.0))
      else
        super points.to_f
      end
    # FIXME HACK assume em value
    elsif points < 1
      super (@font_size * points)
    else
      super points
    end
  end

  def resolve_font_style styles
    if styles.include? :bold
      (styles.include? :italic) ? :bold_italic : :bold
    elsif styles.include? :italic
      :italic
    else
      :normal
    end
  end

  # Retreives the collection of font styles from the given font style key,
  # which defaults to the current font style.
  #
  def font_styles style = font_style
    if style
      style == :bold_italic ? [:bold, :italic].to_set : [style].to_set
    else
      ::Set.new
    end
  end

  # Apply the font settings (family, size, styles and character spacing) from
  # the fragment to the document, then yield to the block.
  #
  # The original font settings are restored before this method returns.
  #
  def fragment_font fragment
    f_info = font_info
    f_family = fragment[:font] || f_info[:family]
    f_size = fragment[:size] || f_info[:size]
    if (f_styles = fragment[:styles])
      f_style = resolve_font_style f_styles
    else
      f_style = :normal
    end

    if (c_spacing = fragment[:character_spacing])
      character_spacing c_spacing do
        font f_family, size: f_size, style: f_style do
          yield
        end
      end
    else
      font f_family, size: f_size, style: f_style do
        yield
      end
    end
  end

  def calc_line_metrics line_height = 1, font = self.font, font_size = self.font_size
    line_height_length = line_height * font_size
    leading = line_height_length - font_size
    half_leading = leading / 2
    padding_top = half_leading + font.line_gap
    padding_bottom = half_leading
    LineMetrics.new line_height_length, leading, padding_top, padding_bottom, false
  end

=begin
  # these line metrics attempted to figure out a correction based on the reported height and the font_size
  # however, it only works for some fonts, and breaks down for fonts like Noto Serif
  def calc_line_metrics line_height = 1, font = self.font, font_size = self.font_size
    line_height_length = font_size * line_height
    line_gap = line_height_length - font_size
    correction = font.height - font_size
    leading = line_gap - correction
    shift = (font.line_gap + correction + line_gap) / 2
    final_gap = font.line_gap != 0
    LineMetrics.new line_height_length, leading, shift, shift, final_gap
  end
=end

  # Parse the text into an array of fragments using the text formatter.
  def parse_text string, options = {}
    return [] if string.nil?

    options = options.dup
    if (format_option = options.delete :inline_format)
      format_option = [] unless format_option.is_a? ::Array
      fragments = self.text_formatter.format string, *format_option 
    else
      fragments = [{text: string}]
    end

    if (color = options.delete :color)
      fragments.map do |fragment|
        fragment[:color] ? fragment : fragment.merge(color: color)
      end
    else
      fragments
    end
  end

  # Performs the same work as text except that the first_line_opts
  # are applied to the first line of text renderered. It's necessary
  # to use low-level APIs in this method so that we only style the
  # first line and not the remaining lines (which is the default
  # behavior in Prawn).
  def text_with_formatted_first_line string, first_line_opts, opts
    color = opts.delete :color
    fragments = parse_text string, opts
    # NOTE the low-level APIs we're using don't recognize the :styles option, so we must resolve
    if (styles = opts.delete :styles)
      opts[:style] = resolve_font_style styles
    end
    if (first_line_styles = first_line_opts.delete :styles)
      first_line_opts[:style] = resolve_font_style first_line_styles
    end
    first_line_color = (first_line_opts.delete :color) || color
    opts = opts.merge document: self
    # QUESTION should we merge more carefully here? (hand-select keys?)
    first_line_opts = opts.merge(first_line_opts).merge single_line: true
    box = ::Prawn::Text::Formatted::Box.new fragments, first_line_opts
    # NOTE get remaining_fragments before we add color to fragments on first line
    remaining_fragments = box.render dry_run: true
    # NOTE color must be applied per-fragment
    if first_line_color
      fragments.each {|fragment| fragment[:color] ||= first_line_color}
    end
    fill_formatted_text_box fragments, first_line_opts
    unless remaining_fragments.empty?
      # NOTE color must be applied per-fragment
      if color
        remaining_fragments.each {|fragment| fragment[:color] ||= color }
      end
      # as of Prawn 1.2.1, we have to handle the line gap after the first line manually
      move_down opts[:leading]
      remaining_fragments = fill_formatted_text_box remaining_fragments, opts
      draw_remaining_formatted_text_on_new_pages remaining_fragments, opts
    end
  end

  # Apply the text transform to the specified text.
  #
  # Supported transform values are "uppercase", "lowercase", or "none" (passed
  # as either a String or a Symbol). When the uppercase transform is applied to
  # the text, it correctly uppercases visible text while leaving markup and
  # named character entities unchanged. The none transform returns the text
  # unmodified.
  #
  def transform_text text, transform
    case transform
    when :uppercase, 'uppercase'
      uppercase_pcdata text
    when :lowercase, 'lowercase'
      lowercase_mb text
    else
      text
    end
  end

  # Cursor

  # Short-circuits the call to the built-in move_up operation
  # when n is 0.
  #
  def move_up n
    super unless n == 0
  end

  # Override built-in move_text_position method to prevent Prawn from advancing
  # to next page if image doesn't fit before rendering image.
  #--
  # NOTE could use :at option when calling image/embed_image instead
  def move_text_position h
  end

  # Short-circuits the call to the built-in move_down operation
  # when n is 0.
  #
  def move_down n
    super unless n == 0
  end

  # Bounds

  # Overrides the built-in pad operation to allow for asymmetric paddings.
  #
  # Example:
  #
  #  pad 20, 10 do
  #    text 'A paragraph with twice as much top padding as bottom padding.'
  #  end
  #
  def pad top, bottom = nil
    move_down top
    yield
    move_down(bottom || top)
  end

  # Combines the built-in pad and indent operations into a single method.
  #
  # Padding may be specified as an array of four values, or as a single value.
  # The single value is used as the padding around all four sides of the box.
  #
  # If padding is nil, this method simply yields to the block and returns.
  #
  # Example:
  #
  #  pad_box 20 do
  #    text 'A paragraph inside a blox with even padding on all sides.'
  #  end
  #
  #  pad_box [10, 10, 10, 20] do
  #    text 'An indented paragraph inside a box with equal padding on all sides.'
  #  end
  #
  def pad_box padding
    if padding
      # TODO implement shorthand combinations like in CSS
      p_top, p_right, p_bottom, p_left = (padding.is_a? ::Array) ? padding : ([padding] * 4)
      begin
        # logic is intentionally inlined
        move_down p_top
        bounds.add_left_padding p_left
        bounds.add_right_padding p_right
        yield
        # NOTE support negative bottom padding for use with quote block
        if p_bottom < 0
          # QUESTION should we return to previous page if top of page is reached?
          p_bottom < cursor - reference_bounds.top ? (move_cursor_to reference_bounds.top) : (move_down p_bottom)
        else
          p_bottom < cursor ? (move_down p_bottom) : reference_bounds.move_past_bottom
        end
      ensure
        bounds.subtract_left_padding p_left
        bounds.subtract_right_padding p_right
      end
    else
      yield
    end

    # alternate, delegated logic
    #pad padding[0], padding[2] do
    #  indent padding[1], padding[3] do
    #    yield
    #  end
    #end
  end

  # Stretch the current bounds to the left and right edges of the current page
  # while yielding the specified block if the verdict argument is true.
  # Otherwise, simply yield the specified block.
  #
  def span_page_width_if verdict
    if verdict
      indent(-bounds_margin_left, -bounds_margin_right) do
        yield
      end
    else
      yield
    end
  end

  # A flowing version of the bounding_box. If the content runs to another page, the cursor starts
  # at the top of the page instead of the original cursor position. Similar to span, except
  # you can specify an absolute left position and pass additional options through to bounding_box.
  #
  def flow_bounding_box left = 0, opts = {}
    original_y = self.y
    canvas do
      bounding_box [margin_box.absolute_left + left, margin_box.absolute_top], opts do
        self.y = original_y
        yield
      end
    end
  end

  # Graphics

  # Fills the current bounding box with the specified fill color. Before
  # returning from this method, the original fill color on the document is
  # restored.
  def fill_bounds f_color = fill_color
    if f_color && f_color != 'transparent'
      prev_fill_color = fill_color
      fill_color f_color
      fill_rectangle bounds.top_left, bounds.width, bounds.height
      fill_color prev_fill_color
    end
  end

  # Fills the absolute bounding box with the specified fill color. Before
  # returning from this method, the original fill color on the document is
  # restored.
  def fill_absolute_bounds f_color = fill_color
    canvas { fill_bounds f_color }
  end

  # Fills the current bounds using the specified fill color and strokes the
  # bounds using the specified stroke color. Sets the line with if specified
  # in the options. Before returning from this method, the original fill
  # color, stroke color and line width on the document are restored.
  #
  def fill_and_stroke_bounds f_color = fill_color, s_color = stroke_color, options = {}
    no_fill = !f_color || f_color == 'transparent'
    no_stroke = !s_color || s_color == 'transparent' || options[:line_width] == 0
    return if no_fill && no_stroke
    save_graphics_state do
      radius = options[:radius] || 0

      # fill
      unless no_fill
        fill_color f_color
        fill_rounded_rectangle bounds.top_left, bounds.width, bounds.height, radius
      end

      # stroke
      unless no_stroke
        stroke_color s_color
        line_width(options[:line_width] || 0.5)
        # FIXME think about best way to indicate dashed borders
        #if options.has_key? :dash_width
        #  dash options[:dash_width], space: options[:dash_space] || 1
        #end
        stroke_rounded_rectangle bounds.top_left, bounds.width, bounds.height, radius
        #undash if options.has_key? :dash_width
      end
    end
  end

  # Fills and, optionally, strokes the current bounds using the fill and
  # stroke color specified, then yields to the block. The only_if option can
  # be used to conditionally disable this behavior.
  #
  def shade_box color, line_color = nil, options = {}
    if (!options.has_key? :only_if) || options[:only_if]
      # FIXME could use save_graphics_state here
      previous_fill_color = current_fill_color
      fill_color color
      fill_rectangle [bounds.left, bounds.top], bounds.right, bounds.top - bounds.bottom
      fill_color previous_fill_color
      if line_color
        line_width 0.5
        previous_stroke_color = current_stroke_color
        stroke_color line_color
        stroke_bounds
        stroke_color previous_stroke_color
      end
    end
    yield
  end

  # A compliment to the stroke_horizontal_rule method, strokes a
  # vertical line using the current bounds. The width of the line
  # can be specified using the line_width option. The horizontal (x)
  # position can be specified using the at option.
  #
  def stroke_vertical_rule rule_color = stroke_color, options = {}
    rule_x = options[:at] || 0
    rule_y_from = bounds.top
    rule_y_to = bounds.bottom
    rule_style = options[:line_style]
    rule_width = options[:line_width] || 0.5
    save_graphics_state do
      line_width rule_width
      stroke_color rule_color
      case rule_style
      when :dashed
        dash rule_width * 4
      when :dotted
        dash rule_width
      when :double
        stroke_vertical_line rule_y_from, rule_y_to, at: (rule_x - rule_width)
        rule_x += rule_width
      end if rule_style
      stroke_vertical_line rule_y_from, rule_y_to, at: rule_x
    end
  end

  # Strokes a horizontal line using the current bounds. The width of the line
  # can be specified using the line_width option.
  #
  def stroke_horizontal_rule rule_color = stroke_color, options = {}
    rule_style = options[:line_style]
    rule_width = options[:line_width] || 0.5
    rule_x_start = bounds.left
    rule_x_end = bounds.right
    rule_inked = false
    save_graphics_state do
      line_width rule_width
      stroke_color rule_color
      case rule_style
      when :dashed
        dash rule_width * 4
      when :dotted
        dash rule_width
      when :double
        move_up rule_width
        stroke_horizontal_line rule_x_start, rule_x_end
        move_down rule_width * 2
        stroke_horizontal_line rule_x_start, rule_x_end
        move_up rule_width
        rule_inked = true
      end if rule_style
      stroke_horizontal_line rule_x_start, rule_x_end unless rule_inked
    end
  end

  # Pages

  # Deletes the current page and move the cursor
  # to the previous page.
  def delete_page
    pg = page_number
    pdf_store = state.store
    pdf_objs = pdf_store.instance_variable_get :@objects
    pdf_ids = pdf_store.instance_variable_get :@identifiers
    page_id = pdf_store.object_id_for_page pg
    content_id = page.content.identifier
    [page_id, content_id].each do |key|
      pdf_objs.delete key
      pdf_ids.delete key
    end
    pdf_store.pages.data[:Kids].pop
    pdf_store.pages.data[:Count] -= 1
    state.pages.pop
    if pg > 1
      go_to_page pg - 1
    else
      @page_number = 0
      state.page = nil
    end
  end

  # Import the specified page into the current document.
  #
  # By default, advance to the subsequent page, creating one if necessary.
  # This behavior can be disabled by passing the option `advance: false`.
  #
  def import_page file, opts = {}
    prev_page_layout = page.layout
    prev_page_size = page.size
    state.compress = false if state.compress # can't use compression if using template
    prev_text_rendering_mode = (defined? @text_rendering_mode) ? @text_rendering_mode : nil
    delete_page if opts[:replace]
    # NOTE use functionality provided by prawn-templates
    start_new_page_discretely template: file
    # prawn-templates sets text_rendering_mode to :unknown, which breaks running content; revert
    @text_rendering_mode = prev_text_rendering_mode
    if opts.fetch :advance, true
      if last_page?
        # NOTE set page size & layout explicitly in case imported page differs
        # I'm not sure it's right to start a new page here, but unfortunately there's no other
        # way atm to prevent the size & layout of the imported page from affecting subsequent pages
        start_new_page size: prev_page_size, layout: prev_page_layout
      else
        go_to_page page_number + 1
      end
    end
    nil
  end

  # Create a new page for the specified image. If the
  # canvas option is true, the image is stretched to the
  # edges of the page (full coverage).
  def image_page file, options = {}
    start_new_page_discretely
    if options[:canvas]
      canvas do
        image file, width: bounds.width, height: bounds.height
      end
    else
      image file, fit: [bounds.width, bounds.height]
    end
    # FIXME shouldn't this be `go_to_page prev_page_number + 1`?
    go_to_page page_count
    nil
  end

  # Perform an operation (such as creating a new page) without triggering the on_page_create callback
  #
  def perform_discretely
    if (saved_callback = state.on_page_create_callback)
      # equivalent to calling `on_page_create`
      state.on_page_create_callback = nil
      yield
      # equivalent to calling `on_page_create &saved_callback`
      state.on_page_create_callback = saved_callback
    else
      yield
    end
  end

  #def advance_or_start_new_page options = {}
  #  if last_page?
  #    start_new_page options
  #  else
  #    go_to_page page_number + 1
  #  end
  #end

  # Start a new page without triggering the on_page_create callback
  #
  def start_new_page_discretely options = {}
    perform_discretely do
      start_new_page options
    end
  end

  # Grouping

  # Conditional group operation
  #
  def group_if verdict
    if verdict
      state.optimize_objects = false # optimize objects breaks group
      group { yield }
    else
      yield
    end
  end

  def get_scratch_document
    # marshal if not using transaction feature
    #Marshal.load Marshal.dump @prototype

    # use cached instance, tests show it's faster
    #@prototype ||= ::Prawn::Document.new
    @scratch ||= if defined? @prototype
      scratch = Marshal.load Marshal.dump @prototype
      scratch.instance_variable_set(:@prototype, @prototype)
      # TODO set scratch number on scratch document
      scratch
    else
      warn 'asciidoctor: WARNING: no scratch prototype available; instantiating fresh scratch document'
      ::Prawn::Document.new
    end
  end

  def scratch?
    (@_label ||= (state.store.info.data[:Scratch] ? :scratch : :primary)) == :scratch
  end
  alias :is_scratch? :scratch?

  # TODO document me
  def dry_run &block
    scratch = get_scratch_document
    scratch.start_new_page
    start_page_number = scratch.page_number
    start_y = scratch.y
    if (left_padding = bounds.total_left_padding) > 0
      scratch.bounds.add_left_padding left_padding
    end
    if (right_padding = bounds.total_right_padding) > 0
      scratch.bounds.add_right_padding right_padding
    end
    scratch.font font_family, style: font_style, size: font_size do
      scratch.instance_exec(&block)
    end
    # NOTE don't count excess if cursor exceeds writable area (due to padding)
    partial_page_height = [effective_page_height, start_y - scratch.y].min
    scratch.bounds.subtract_left_padding left_padding if left_padding > 0
    scratch.bounds.subtract_right_padding right_padding if right_padding > 0
    whole_pages = scratch.page_number - start_page_number
    [(whole_pages * bounds.height + partial_page_height), whole_pages, partial_page_height]
  end

  # Attempt to keep the objects generated in the block on the same page
  #
  # TODO short-circuit nested usage
  def keep_together &block
    available_space = cursor
    total_height, _whole_pages, _remainder = dry_run(&block)
    # NOTE technically, if we're at the page top, we don't even need to do the
    # dry run, except several uses of this method rely on the calculated height
    if total_height > available_space && !at_page_top? && total_height <= effective_page_height
      start_new_page
      started_new_page = true
    else
      started_new_page = false
    end
    
    # HACK yield doesn't work here on JRuby (at least not when called from AsciidoctorJ)
    #yield remainder, started_new_page
    instance_exec(total_height, started_new_page, &block)
  end

  # Attempt to keep the objects generated in the block on the same page
  # if the verdict parameter is true.
  #
  def keep_together_if verdict, &block
    if verdict
      keep_together(&block)
    else
      yield
    end
  end

=begin
  def run_with_trial &block
    available_space = cursor
    total_height, whole_pages, remainder = dry_run(&block)
    if whole_pages > 0 || remainder > available_space
      started_new_page = true
    else
      started_new_page = false
    end
    # HACK yield doesn't work here on JRuby (at least not when called from AsciidoctorJ)
    #yield remainder, started_new_page
    instance_exec(remainder, started_new_page, &block)
  end
=end
end
end
end
