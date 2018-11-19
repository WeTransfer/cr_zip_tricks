class Crzt::OffsetIO < IO
  def initialize(any_io : IO)
    @io = any_io
    @offset = 0_u64
  end

  def offset
    @offset
  end

  def advance(by : Int)
    @offset += by
  end

  # Does nothing but must be implemented since Crystal does not differentiate
  # between Writesr/Readers
  def read(slice : Bytes)
    raise IO::Error.new "Can't read from CRC32Writer"
  end

  def write(slice : Bytes)
    @io.write(slice)
    @offset += slice.size
    nil
  end
end
