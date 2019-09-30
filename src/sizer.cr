require "./streamer"

class ZipTricks::Sizer
  private class NullIO < IO
    def read(slice : Bytes)
      raise IO::Error.new "Can't read from NullIO"
    end

    def write(slice : Bytes) : Nil
      nil
    end
  end

  def self.size
    streamer = ZipTricks::Streamer.new(NullIO.new)
    sizer = new(streamer)

    yield(sizer)

    streamer.finish
    streamer.bytesize
  end

  def initialize(streamer : ZipTricks::Streamer)
    @streamer = streamer
  end

  def predeclare_entry(filename : String, uncompressed_size : Int, compressed_size : Int, use_data_descriptor : Bool = false)
    @streamer.predeclare_entry(filename: filename,
      uncompressed_size: uncompressed_size,
      compressed_size: compressed_size,
      use_data_descriptor: use_data_descriptor,
      crc32: 0,
      storage_mode: 0)
    @streamer.advance(compressed_size)
    if use_data_descriptor
      @streamer.write_data_descriptor_for_last_entry
    end
  end
end
