require 'json'
require 'rmagick'

# Represents a Jackbox drawing. Each line has a width and collection of
# connected points.
class Drawing
  MSG_PREFIX = '5:::'

  IMAGE_HEIGHT = 75
  IMAGE_WIDTH = 75

  CANVAS_HEIGHT = 300
  CANVAS_WIDTH = 300

  VERT_SCALE = CANVAS_HEIGHT / IMAGE_HEIGHT
  HORIZ_SCALE = CANVAS_WIDTH / IMAGE_WIDTH
  BRUSH_SIZE = [VERT_SCALE, HORIZ_SCALE].max + 2

  COLOR_DEPTH = 16

  IMAGE_EXTS = %w{.jpg .jpeg .png .gif .webp}

  def initialize()
    @lines = []
    @background = '#000000'
  end

  def self.find_images(path)
    candidates = []
    Find.find(path) do |subpath|
      ending_matches = IMAGE_EXTS.any? do |ext|
        subpath.end_with?(ext)
      end

      if !FileTest.directory?(subpath) && ending_matches
        begin
          image = Magick::ImageList.new(subpath)[0]

          if image.opaque?
            candidates << subpath
          end
        rescue Magick::ImageMagickError
          Find.prune()
        end

        # Free memory
        if image && !image.destroyed?
          image.destroy!
        end
      end
    end

    return candidates
  end


  def load_image(filepath)
    # TODO: strip opacity
    original = Magick::ImageList.new(filepath)[0]
    resized = original.resize_to_fit(IMAGE_HEIGHT, IMAGE_WIDTH)
    quantized = resized.quantize(
      COLOR_DEPTH,
      Magick::RGBColorspace,
      Magick::NoDitherMethod
    )

    _image_to_lines(quantized)
  end

  # Turns an image into the drawing format. Represents lines as two points
  # each, draw from left to right.
  def _image_to_lines(image)
    @lines = []
    last_pixel = image.get_pixels(0, 0, 1, 1)[0]

    current_line = {
      'thickness' => BRUSH_SIZE,
      'color' => last_pixel.to_color(Magick::SVGCompliance, false, 8, true),
      'points' => [{'x' => 0, 'y' => 0}],
    }

    image.each_pixel do |pixel, column, row|
      color = pixel.to_color(Magick::SVGCompliance, false, 8, true)

      # Current line ends when we're at the final column or the color changes
      if pixel != last_pixel && column != 0
        current_line['points'] << {
          'x' => (column - 1) * HORIZ_SCALE,
          'y' => row * VERT_SCALE,
        }
        @lines << current_line
      end

      # Start a new line when the color changes or we're on a new row
      if pixel != last_pixel || column == 0
        current_line = {
          'thickness' => BRUSH_SIZE,
          'color' => pixel.to_color(Magick::SVGCompliance, false, 8, true),
          'points' => [{
            'x' => column * HORIZ_SCALE,
            'y' => row * VERT_SCALE,
          }],
        }
      end

      if column == (IMAGE_WIDTH - 1)
        current_line['points'] << {
          'x' => column * HORIZ_SCALE,
          'y' => row * VERT_SCALE,
        }
        @lines << current_line
      end

      last_pixel = pixel
    end
  end

  # Converts the drawing into the format used by Jackbox.
  def to_message(
    code,
    uuid,
    appid,
    message_key='pictureLines',
    include_bg=true,
    playerpic=false
  )
    msg_obj = {
      "name" => "msg",
      "args" => [{
        "roomId" => code,
        "userId" => uuid,
        "message" => {
          message_key => @lines,
        },
        "type" => "Action",
        "appId" => appid,
        "action" => "SendMessageToRoomOwner",
      }]
    }

    if include_bg
      msg_obj['args'][0]['message']['background'] = @background
    end

    if playerpic
      msg_obj['args'][0]['message']['setPlayerPicture'] = true
    end

    return MSG_PREFIX + JSON.generate(msg_obj)
  end

  def valid?
    return @lines.all? do |line|
      line.is_a?(Hash) &&
        !line['thickness'].nil? &&
        !line['color'].nil? &&
        line['points'].is_a?(Array) &&
        line['points'].all? do |point|
          point.is_a?(Hash) &&
            point['x'].is_a?(Numeric) &&
            point['y'].is_a?(Numeric) &&
            point['x'] >= 0 &&
            point['x'] <= CANVAS_WIDTH &&
            point['y'] >= 0 &&
            point['y'] <= CANVAS_HEIGHT
        end
    end
  end
end
