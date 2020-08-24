require "./writer"
require "./offset_io"
require "./crc32_writer"
require "compress/deflate"

class ZipTricks::Streamer
  STORED   = 0
  DEFLATED = 8

  class DuplicateFilename < ArgumentError
  end

  class Entry
    property filename = ""
    property entry_offset_in_file = 0_u64
    property crc32 = Digest::CRC32.initial
    property uncompressed_size = 0_u64
    property compressed_size = 0_u64
    property use_data_descriptor = false
    property storage_mode = 0 # Stored

    # Get the general purpose flags for the entry. We care about is the EFS
    # bit (bit 11) which should be set if the filename is UTF8. If it is, we need to set the
    # bit so that the unarchiving application knows that the filename in the archive is UTF-8
    # encoded, and not some DOS default. For ASCII entries it does not matter.
    # Additionally, we care about bit 3 which toggles the use of the postfix data descriptor.

    def gp_flags
      flag = 0b00000000000
      flag |= 0b100000000000                 # if @requires_efs_flag # bit 11
      flag |= 0x0008 if @use_data_descriptor # bit 3
      flag
    end
  end

  def initialize(io : IO)
    @raw_io = io
    @io = ZipTricks::OffsetIO.new(@raw_io)
    @filenames = Set(String).new
    @entries = Array(Entry).new
    @writer = ZipTricks::Writer.new
  end

  def self.archive(io : IO)
    streamer = new(io)
    yield streamer
    streamer.finish
  end

  def finish
    write_central_directory
    @filenames.clear
    @entries.clear
  end

  def predeclare_entry(filename : String, uncompressed_size : Int, compressed_size : Int, crc32 : Int, storage_mode : Int, use_data_descriptor : Bool = false)
    entry = Entry.new
    entry.filename = filename
    entry.use_data_descriptor = false
    entry.storage_mode = storage_mode
    entry.entry_offset_in_file = @io.offset
    entry.use_data_descriptor = use_data_descriptor
    entry.uncompressed_size = uncompressed_size.to_u64
    entry.compressed_size = uncompressed_size.to_u64
    entry.crc32 = crc32.to_u32

    check_dupe_filename!(filename)
    @entries << entry
    write_local_entry_header(entry)
  end

  def add_stored(filename : String)
    predeclare_entry(filename, uncompressed_size: 0, compressed_size: 0, crc32: 0, storage_mode: STORED, use_data_descriptor: true)
    sizer = ZipTricks::OffsetIO.new(@io)
    checksum = ZipTricks::CRC32Writer.new(sizer)

    yield checksum # for writing, the caller can write to it as an IO

    last_entry = @entries.last
    last_entry.uncompressed_size = sizer.offset
    last_entry.compressed_size = sizer.offset
    last_entry.crc32 = checksum.crc32
    write_data_descriptor_for_last_entry
  end

  def add_deflated(filename : String)
    predeclare_entry(filename, uncompressed_size: 0, compressed_size: 0, crc32: 0, storage_mode: DEFLATED, use_data_descriptor: true)
    # The "IO sandwich"
    compressed_sizer = ZipTricks::OffsetIO.new(@io)
    flater_io = Compress::Deflate::Writer.new(compressed_sizer)
    uncompressed_sizer = ZipTricks::OffsetIO.new(flater_io)
    checksum = ZipTricks::CRC32Writer.new(uncompressed_sizer)

    yield checksum # for writing, the caller can write to it as an IO

    flater_io.close # To finish generating the deflated block
    last_entry = @entries.last
    last_entry.uncompressed_size = uncompressed_sizer.offset
    last_entry.compressed_size = compressed_sizer.offset
    last_entry.crc32 = checksum.crc32
    write_data_descriptor_for_last_entry
  end

  def write_data_descriptor_for_last_entry
    entry = @entries[-1]
    @writer.write_data_descriptor(io: @io,
      compressed_size: entry.compressed_size,
      uncompressed_size: entry.uncompressed_size,
      crc32: entry.crc32)
  end

  def write_local_entry_header(entry)
    @writer.write_local_file_header(io: @io,
      filename: entry.filename,
      compressed_size: entry.compressed_size,
      uncompressed_size: entry.uncompressed_size,
      crc32: entry.crc32,
      gp_flags: entry.gp_flags,
      mtime: Time.utc,
      storage_mode: entry.storage_mode)
  end

  def advance(by)
    @io.advance(by)
  end

  def bytesize
    @io.offset
  end

  def write_central_directory
    cdir_starts_at = @io.offset
    @entries.each do |entry|
      @writer.write_central_directory_file_header(io: @io,
        filename: entry.filename,
        compressed_size: entry.compressed_size,
        uncompressed_size: entry.uncompressed_size,
        crc32: entry.crc32,
        gp_flags: entry.gp_flags,
        mtime: Time.utc,
        storage_mode: entry.storage_mode,
        local_file_header_location: entry.entry_offset_in_file)
    end
    cdir_ends_at = @io.offset
    cdir_size = cdir_ends_at - cdir_starts_at
    @writer.write_end_of_central_directory(io: @io,
      start_of_central_directory_location: cdir_starts_at,
      central_directory_size: @io.offset - cdir_starts_at,
      num_files_in_archive: @entries.size)
  end

  private def check_dupe_filename!(filename)
    if @filenames.includes?(filename)
      raise(DuplicateFilename.new("The archive already contains an entry named #{filename.inspect}"))
    else
      @filenames.add(filename)
    end
  end
end
