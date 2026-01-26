# frozen_string_literal: true

require "mini_magick"
require "base64"

# PDF to Base64 image conversion service
# Uses MiniMagick with Poppler for PDF rendering
class PdfConverterService
  class ConversionError < StandardError; end

  def initialize
    @config = Rails.application.config.ocr.image
  end

  # Convert PDF or image file to Base64-encoded JPEG
  #
  # @param file_path [String] Path to PDF or image file
  # @return [String, nil] Base64-encoded image string, or nil if conversion fails
  def convert_to_base64(file_path)
    validate_file!(file_path)

    image = load_image(file_path)
    image = resize_if_needed(image)
    image = convert_to_jpeg(image)

    encode_to_base64(image)
  rescue MiniMagick::Error => e
    Rails.logger.error "[PdfConverter] MiniMagick error: #{e.message}"
    nil
  rescue StandardError => e
    Rails.logger.error "[PdfConverter] Conversion failed: #{e.message}"
    Rails.logger.error e.backtrace&.first(5)&.join("\n")
    nil
  end

  private

  def validate_file!(file_path)
    unless file_path.present? && File.exist?(file_path)
      raise ConversionError, "File not found: #{file_path}"
    end

    unless File.readable?(file_path)
      raise ConversionError, "File not readable: #{file_path}"
    end
  end

  def load_image(file_path)
    ext = File.extname(file_path).downcase

    if ext == ".pdf"
      load_pdf_as_image(file_path)
    else
      MiniMagick::Image.open(file_path)
    end
  end

  def load_pdf_as_image(file_path)
    Rails.logger.info "[PdfConverter] Converting PDF to image: #{File.basename(file_path)}"

    # Use MiniMagick to convert PDF first page to image
    # density = DPI setting for PDF rendering
    image = MiniMagick::Image.open(file_path) do |config|
      config.density @config[:dpi]
    end

    # For multi-page PDFs, get only first page
    # MiniMagick loads first page by default for PDFs
    image.format "jpeg"

    Rails.logger.info "[PdfConverter] PDF converted: #{image.width}x#{image.height}"
    image
  end

  def resize_if_needed(image)
    max_dim = @config[:max_dimension]
    return image if image.width <= max_dim && image.height <= max_dim

    Rails.logger.info "[PdfConverter] Resizing from #{image.width}x#{image.height}"

    # Calculate new dimensions maintaining aspect ratio
    if image.width > image.height
      new_width = max_dim
      new_height = (image.height * max_dim / image.width.to_f).to_i
    else
      new_height = max_dim
      new_width = (image.width * max_dim / image.height.to_f).to_i
    end

    image.resize "#{new_width}x#{new_height}"
    Rails.logger.info "[PdfConverter] Resized to #{new_width}x#{new_height}"

    image
  end

  def convert_to_jpeg(image)
    # Ensure RGB colorspace (convert from CMYK, etc.)
    image.colorspace "sRGB" unless image.data["colorspace"] == "sRGB"

    # Convert to JPEG with quality setting
    image.format "jpeg"
    image.quality @config[:quality]

    image
  end

  def encode_to_base64(image)
    # Get binary blob and encode
    blob = image.to_blob
    encoded = Base64.strict_encode64(blob)

    Rails.logger.info "[PdfConverter] Encoded to Base64: #{encoded.length} chars"
    encoded
  end
end
