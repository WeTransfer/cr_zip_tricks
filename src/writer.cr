class Crzt::Writer
  FOUR_BYTE_MAX_UINT              =         0xFFFFFFFF
  TWO_BYTE_MAX_UINT               =             0xFFFF
  EIGHT_BYTE_MAX_UINT             = 0xFFFFFFFFFFFFFFFF
  CRZT_COMMENT                    = "Written using crzt"
  VERSION_NEEDED_TO_EXTRACT       = 20
  VERSION_NEEDED_TO_EXTRACT_ZIP64 = 45

  # A combination of the VERSION_MADE_BY low byte and the OS type high byte
  # VERSION_MADE_BY = 52
  # os_type = 3 # UNIX
  # [VERSION_MADE_BY, os_type].pack('CC')
  MADE_BY_SIGNATURE = Bytes[52, 3]

  def file_external_attrs
    # These need to be set so that the unarchived files do not become executable on UNIX, for
    # security purposes. Strictly speaking we would want to make this user-customizable,
    # but for now just putting in sane defaults will do. For example, Trac with zipinfo does this:
    # zipinfo.external_attr = 0644 << 16L # permissions -r-wr--r--.
    # We snatch the incantations from Rubyzip for this.
    unix_perms = 0o644
    file_type_file = 0o10
    (file_type_file << 12 | (unix_perms & 0o7777)) << 16
  end

  def dir_external_attrs
    # Applies permissions to an empty directory.
    unix_perms = 0o755
    file_type_dir = 0o04
    (file_type_dir << 12 | (unix_perms & 0o7777)) << 16
  end

  alias ZipLocation = Int
  alias ZipFilesize = Int
  alias ZipCRC32 = Int
  alias ZipGpFlags = Int
  alias ZipStorageMode = Int

  BE = IO::ByteFormat::BigEndian

  def to_binary_dos_time(t : Time)
    (t.second / 2) + (t.minute << 5) + (t.hour << 11)
  end

  def to_binary_dos_date(t : Time)
    t.day + (t.month << 5) + ((t.year - 1980) << 9)
  end

  def write_uint8_le(io : IO, val : Int)
    #  if val < 0 || val > 0xFF
    #    raise(ArgumentError.new("Given value would overflow"))
    #  end
    io.write_bytes(val.to_u8, IO::ByteFormat::LittleEndian)
  end

  def write_uint16_le(io : IO, val : Int)
    if val < 0 || val > TWO_BYTE_MAX_UINT
      raise(ArgumentError.new("Given value would overflow"))
    end
    io.write_bytes(val.to_u16, IO::ByteFormat::LittleEndian)
  end

  def write_uint32_le(io : IO, val : Int)
    #   if val > (FOUR_BYTE_MAX_UINT + 1) || val < 0
    #      raise(ArgumentError.new("Given value would overflow. #{val} with #{FOUR_BYTE_MAX_UINT} max"))
    #    end
    io.write_bytes(val.to_u32, IO::ByteFormat::LittleEndian)
  end

  def write_int32_le(io : IO, val : Int)
    #   if val > (FOUR_BYTE_MAX_UINT + 1) || val < 0
    #      raise(ArgumentError.new("Given value would overflow. #{val} with #{FOUR_BYTE_MAX_UINT} max"))
    #    end
    io.write_bytes(val.to_i32, IO::ByteFormat::LittleEndian)
  end

  def write_uint64_le(io : IO, val : Int)
    if val < 0 || val > EIGHT_BYTE_MAX_UINT
      raise(ArgumentError.new("Given value would overflow"))
    end
    io.write_bytes(val.to_u64, IO::ByteFormat::LittleEndian)
  end

  def write_zip64_extra_for_local_file_header(io : IO, compressed_size : ZipFilesize, uncompressed_size : ZipFilesize)
    write_uint16_le(io, 0x0001)            # Tag for the extra field
    write_uint16_le(io, 16)                # Size of the extra field
    write_uint64_le(io, uncompressed_size) # Original uncompressed size
    write_uint64_le(io, compressed_size)   # Size of compressed data
  end

  def write_local_file_header(io : IO, filename : String, compressed_size : ZipFilesize, uncompressed_size : ZipFilesize, crc32 : ZipCRC32, gp_flags : ZipGpFlags, mtime : Time, storage_mode : ZipStorageMode)
    requires_zip64 = (compressed_size > FOUR_BYTE_MAX_UINT || uncompressed_size > FOUR_BYTE_MAX_UINT)

    write_uint32_le(io, 0x04034b50)
    if requires_zip64
      write_uint16_le(io, VERSION_NEEDED_TO_EXTRACT_ZIP64)
    else
      write_uint16_le(io, VERSION_NEEDED_TO_EXTRACT)
    end

    write_uint16_le(io, gp_flags)                  # general purpose bit flag        2 bytes
    write_uint16_le(io, storage_mode)              # compression method              2 bytes
    write_uint16_le(io, to_binary_dos_time(mtime)) # last mod file time              2 bytes
    write_uint16_le(io, to_binary_dos_date(mtime)) # last mod file date              2 bytes
    write_uint32_le(io, crc32)                     # CRC32                           4 bytes

    # compressed size              4 bytes
    # uncompressed size            4 bytes
    if requires_zip64
      write_uint32_le(io, FOUR_BYTE_MAX_UINT)
      write_uint32_le(io, FOUR_BYTE_MAX_UINT)
    else
      write_uint32_le(io, compressed_size)
      write_uint32_le(io, uncompressed_size)
    end

    # Filename should not be longer than 0xFFFF otherwise this wont fit here
    write_uint16_le(io, filename.bytesize)

    extra_fields_io = IO::Memory.new

    # Interesting tidbit:
    # https://social.technet.microsoft.com/Forums/windows/en-US/6a60399f-2879-4859-b7ab-6ddd08a70948
    # TL;DR of it is: Windows 7 Explorer _will_ open Zip64 entries. However, it desires to have the
    # Zip64 extra field as _the first_ extra field.
    if requires_zip64
      write_zip64_extra_for_local_file_header(extra_fields_io, compressed_size, uncompressed_size)
    end
    write_timestamp_extra_field(extra_fields_io, mtime)

    write_uint16_le(io, extra_fields_io.size) # extra field length              2 bytes
    extra_fields_io.rewind

    io << filename # file name (variable size)
    IO.copy(extra_fields_io, io)
  end

  def write_central_directory_file_header(io : IO, filename : String, compressed_size : ZipFilesize, uncompressed_size : ZipFilesize, crc32 : ZipCRC32, gp_flags : ZipGpFlags, mtime : Time, storage_mode : ZipStorageMode, local_file_header_location : ZipLocation)
    # At this point if the header begins somewhere beyound 0xFFFFFFFF we _have_ to record the offset
    # of the local file header as a zip64 extra field, so we give up, give in, you loose, love will always win...
    add_zip64 = (local_file_header_location > FOUR_BYTE_MAX_UINT) || (compressed_size > FOUR_BYTE_MAX_UINT) || (uncompressed_size > FOUR_BYTE_MAX_UINT)

    write_uint32_le(io, 0x02014b50) # central file header signature   4 bytes  (0x02014b50)
    io.write(MADE_BY_SIGNATURE)     # version made by                 2 bytes
    if add_zip64                    # version needed to extract       2 bytes
      write_uint16_le(io, VERSION_NEEDED_TO_EXTRACT_ZIP64)
    else
      write_uint16_le(io, VERSION_NEEDED_TO_EXTRACT)
    end

    write_uint16_le(io, gp_flags)                  # general purpose bit flag        2 bytes
    write_uint16_le(io, storage_mode)              # compression method              2 bytes
    write_uint16_le(io, to_binary_dos_time(mtime)) # last mod file time              2 bytes
    write_uint16_le(io, to_binary_dos_date(mtime)) # last mod file date              2 bytes
    write_uint32_le(io, crc32)                     # crc-32                          4 bytes

    write_uint32_le(io, add_zip64 ? FOUR_BYTE_MAX_UINT : compressed_size)
    write_uint32_le(io, add_zip64 ? FOUR_BYTE_MAX_UINT : uncompressed_size)

    # Filename should not be longer than 0xFFFF otherwise this wont fit here
    write_uint32_le(io, filename.bytesize) # file name length                2 bytes

    extra_fields_io = IO::Memory.new
    if add_zip64
      write_zip64_extra_for_central_directory_file_header(extra_fields_io, local_file_header_location, compressed_size, uncompressed_size)
    end
    write_timestamp_extra_field(extra_fields_io, mtime)

    write_uint16_le(io, extra_fields_io.size) # extra field length              2 bytes
    write_uint16_le(io, 0)                    # file comment length             2 bytes

    # For The Unarchiver < 3.11.1 this field has to be set to the overflow value if zip64 is used
    # because otherwise it does not properly advance the pointer when reading the Zip64 extra field
    # https://bitbucket.org/WAHa_06x36/theunarchiver/pull-requests/2/bug-fix-for-zip64-extra-field-parser/diff
    write_uint16_le(io, add_zip64 ? TWO_BYTE_MAX_UINT : 0) # disk number start               2 bytes
    write_uint16_le(io, 0)                                 # internal file attributes        2 bytes

    # Because the add_empty_directory method will create a directory with a trailing "/",
    # this check can be used to assign proper permissions to the created directory.
    # external file attributes        4 bytes
    exattrs = filename.ends_with?('/') ? dir_external_attrs : file_external_attrs
    write_uint32_le(io, exattrs)

    header_offset = add_zip64 ? FOUR_BYTE_MAX_UINT : local_file_header_location
    write_uint32_le(io, header_offset) # relative offset of local header 4 bytes

    io << filename # file name (variable size)

    extra_fields_io.rewind
    IO.copy(extra_fields_io, io) # extra field (variable size)
    # (empty)                                          # file comment (variable size)
  end

  def write_zip64_extra_for_central_directory_file_header(io : IO, compressed_size : Int, uncompressed_size : Int, local_file_header_location : ZipLocation)
    write_uint16_le(io, 0x0001)            # 2 bytes    Tag for this "extra" block type
    write_uint16_le(io, 28)                # 2 bytes    Size of this "extra" block. For us it will always be 28
    write_uint64_le(io, uncompressed_size) # 2 bytes    Size of uncompressed data
    write_uint64_le(io, compressed_size)   # 2 bytes      Size of compressed data
    write_uint32_le(io, 0)                 # 4 bytes    Number of the disk on which this file starts
  end

  def write_end_of_central_directory(io : IO, start_of_central_directory_location : ZipLocation, central_directory_size : ZipLocation, num_files_in_archive : ZipLocation, comment : String = CRZT_COMMENT)
    zip64_eocdr_offset = start_of_central_directory_location + central_directory_size
    zip64_required = central_directory_size > FOUR_BYTE_MAX_UINT ||
                     start_of_central_directory_location > FOUR_BYTE_MAX_UINT ||
                     zip64_eocdr_offset > FOUR_BYTE_MAX_UINT ||
                     num_files_in_archive > TWO_BYTE_MAX_UINT

    # Then, if zip64 is used
    if zip64_required
      # [zip64 end of central directory record]
      # zip64 end of central dir
      write_uint32_le(io, 0x06064b50) # signature                       4 bytes  (0x06064b50)
      write_uint64_le(io, 44)         # size of zip64 end of central
      # directory record                8 bytes
      # (this is ex. the 12 bytes of the signature and the size value itself).
      # Without the extensible data sector (which we are not using)
      # it is always 44 bytes.
      io.write(MADE_BY_SIGNATURE)                          # version made by                 2 bytes
      write_uint16_le(io, VERSION_NEEDED_TO_EXTRACT_ZIP64) # version needed to extract       2 bytes
      write_uint32_le(io, 0)                               # number of this disk             4 bytes
      write_uint32_le(io, 0)                               # number of the disk with the start of the central directory  4 bytes
      write_uint64_le(io, num_files_in_archive)            # total number of entries in the central directory on this disk  8 bytes
      write_uint64_le(io, num_files_in_archive)            # total number of entries in the archive total 8 bytes
      write_uint64_le(io, central_directory_size)          # size of the central directory   8 bytes

      # offset of start of central directory with respect to the starting disk number        8 bytes
      write_uint64_le(io, start_of_central_directory_location)
      # zip64 extensible data sector    (variable size), blank for us

      # [zip64 end of central directory locator]
      write_uint32_le(io, 0x07064b50)         # zip64 end of central dir locator signature 4 bytes  (0x07064b50)
      write_uint32_le(io, 0)                  # number of the disk with the start of the zip64 end of central directory 4 bytes
      write_uint64_le(io, zip64_eocdr_offset) # relative offset of the zip64
      # end of central directory record 8 bytes
      # (note: "relative" is actually "from the start of the file")
      write_uint32_le(io, 1) # total number of disks           4 bytes
    end

    # Then the end of central directory record:
    write_uint32_le(io, 0x06054b50) # end of central dir signature     4 bytes  (0x06054b50)
    write_uint16_le(io, 0)          # number of this disk              2 bytes
    write_uint16_le(io, 0)          # number of the disk with the
    # start of the central directory 2 bytes

    num_entries = zip64_required ? TWO_BYTE_MAX_UINT : num_files_in_archive
    write_uint16_le(io, num_entries) # total number of entries in the central directory on this disk   2 bytes
    write_uint16_le(io, num_entries) # total number of entries in the central directory            2 bytes

    write_uint32_le(io, zip64_required ? FOUR_BYTE_MAX_UINT : central_directory_size)              # size of the central directory    4 bytes
    write_uint32_le(io, zip64_required ? FOUR_BYTE_MAX_UINT : start_of_central_directory_location) # offset of start of central directory with respect to the starting disk number        4 bytes
    write_uint16_le(io, comment.bytesize)                                                          # .ZIP file comment length        2 bytes
    io << comment                                                                                  # .ZIP file comment       (variable size)
  end

  def write_data_descriptor(io : IO, compressed_size : ZipFilesize, uncompressed_size : ZipFilesize, crc32 : ZipCRC32)
    write_uint32_le(io, 0x08074b50) # Although not originally assigned a signature, the value
    # 0x08074b50 has commonly been adopted as a signature value
    # for the data descriptor record.
    write_uint32_le(io, crc32) # crc-32                          4 bytes

    # If one of the sizes is above 0xFFFFFFF use ZIP64 lengths (8 bytes) instead. A good unarchiver
    # will decide to unpack it as such if it finds the Zip64 extra for the file in the central directory.
    # So also use the opportune moment to switch the entry to Zip64 if needed
    requires_zip64 = (compressed_size > FOUR_BYTE_MAX_UINT || uncompressed_size > FOUR_BYTE_MAX_UINT)

    # compressed size                 4 bytes, or 8 bytes for ZIP64
    # uncompressed size               4 bytes, or 8 bytes for ZIP64
    if requires_zip64
      write_uint64_le(io, compressed_size)
      write_uint64_le(io, uncompressed_size)
    else
      write_uint32_le(io, compressed_size)
      write_uint32_le(io, uncompressed_size)
    end
  end

  # Writes the extended timestamp information field. The spec defines 2
  # different formats - the one for the local file header can also accomodate the
  # atime and ctime, whereas the one for the central directory can only take
  # the mtime - and refers the reader to the local header extra to obtain the
  # remaining times
  def write_timestamp_extra_field(io : IO, mtime : Time)
    #         Local-header version:
    #
    #         Value         Size        Description
    #         -----         ----        -----------
    # (time)  0x5455        Short       tag for this extra block type ("UT")
    #         TSize         Short       total data size for this block
    #         Flags         Byte        info bits
    #         (ModTime)     Long        time of last modification (UTC/GMT)
    #         (AcTime)      Long        time of last access (UTC/GMT)
    #         (CrTime)      Long        time of original creation (UTC/GMT)
    #
    #         Central-header version:
    #
    #         Value         Size        Description
    #         -----         ----        -----------
    # (time)  0x5455        Short       tag for this extra block type ("UT")
    #         TSize         Short       total data size for this block
    #         Flags         Byte        info bits (refers to local header!)
    #         (ModTime)     Long        time of last modification (UTC/GMT)
    #
    # The lower three bits of Flags in both headers indicate which time-
    #       stamps are present in the LOCAL extra field:
    #
    #       bit 0           if set, modification time is present
    #       bit 1           if set, access time is present
    #       bit 2           if set, creation time is present
    #       bits 3-7        reserved for additional timestamps; not set
    flags = 0b10000000                # Set bit 1 only to indicate only mtime is present
    write_uint16_le(io, 0x5455)       # tag for this extra block type ("UT")
    write_uint16_le(io, 1 + 4)        # # the size of this block (1 byte used for the Flag + 1 long used for the timestamp)
    write_uint8_le(io, flags)         # encode a single byte
    write_int32_le(io, mtime.to_unix) # Use a signed long, not the unsigned one used by the rest of the ZIP spec.
  end
end

# io = STDERR # IO::Memory.new
# w = Crzt::Writer.new
# w.write_local_file_header(io, filename = "foobar.txt", compressed_size = 999999, uncompressed_size = 999999, crc32 = 1234, gp_flags = 12, Time.now, storage_mode = 8)
# w.write_central_directory_file_header(io, filename = "foobar.txt", compressed_size = 999999, uncompressed_size = 999999, crc32 = 1234, gp_flags = 12, Time.now, storage_mode = 8, offset = 99)
# w.write_end_of_central_directory(io, start_of_central_directory_location = 7879, central_directory_size = 6789, num_files_in_archive = 3, comment = "Ohai!")

# write_uint64_le(io, 99999998999999999)
# io.size
# io.rewind
# io.gets(999)
# io.gets(8) # => "\u{4}\u{3}\u{2}\u{1}"
