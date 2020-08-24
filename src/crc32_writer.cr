require "digest/crc32"

class ZipTricks::CRC32Writer < IO
  getter count = 0_u32
  getter crc32 = Digest::CRC32.initial
  getter io : IO

  def initialize(io : IO)
    @io = io
  end

  # Does nothing but must be implemented since Crystal does not differentiate
  # between Writesr/Readers
  def read(slice : Bytes)
    raise IO::Error.new "Can't read from CRC32Writer"
  end

  def write(slice : Bytes) : Nil
    return if slice.empty?
    @crc32 = Digest::CRC32.update(slice, @crc32)
    @io.write(slice)
    nil
  end
end
