require "./streamer"

class Crzt::Sizer
  private class NullIO < IO
    def read(slice : Bytes)
    end

    def write(slice : Bytes)
      nil
    end
  end

  def self.size
    streamer = Crzt::Streamer.new(NullIO.new)
    sizer = new(streamer)

    yield(sizer)

    streamer.finish
    streamer.bytesize
  end

  def initialize(streamer : Crzt::Streamer)
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

size = Crzt::Sizer.size do |s|
  s.predeclare_entry(filename: "deflated1.txt", uncompressed_size: 8969887, compressed_size: 1245, use_data_descriptor: true)
  s.predeclare_entry(filename: "deflated2.txt", uncompressed_size: 4568, compressed_size: 4065, use_data_descriptor: true)
end
puts size
