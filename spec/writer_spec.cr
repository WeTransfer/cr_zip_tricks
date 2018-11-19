require "./spec_helper"

class ByteReader
  def initialize(io : IO)
    @io = io
    @io.rewind
  end

  def read_1b
    slice = read_n(1)
    slice[0]
  end

  def read_2b
    @io.read_bytes(UInt16, format = IO::ByteFormat::LittleEndian)
  end

  def read_2c
    # reads a binary string of 2 bytes
    @io.read_bytes(UInt16, format = IO::ByteFormat::LittleEndian)
  end

  def read_4b
    @io.read_bytes(UInt32, format = IO::ByteFormat::LittleEndian)
  end

  def read_8b
    @io.read_bytes(UInt64, format = IO::ByteFormat::LittleEndian)
  end

  def read_4b_signed
    @io.read_bytes(Int32, format = IO::ByteFormat::LittleEndian)
  end

  def read_string_of(n)
    @io.read_string(bytesize: n)
  end

  def read_n(n)
    slice = Bytes.new(n)
    @io.read_fully(slice)
    slice
  end
end

describe ZipTricks::Writer do
  describe "#write_local_file_header" do
    it "writes the local file header for an entry that does not require Zip64" do
      buf = IO::Memory.new
      mtime = Time.utc(2016, 7, 17, 13, 48)

      ZipTricks::Writer.new.write_local_file_header(io: buf,
        filename: "foo.bin",
        compressed_size: 768,
        uncompressed_size: 901,
        crc32: 456,
        gp_flags: 12,
        mtime: mtime,
        storage_mode: 8)

      br = ByteReader.new(buf)
      br.read_4b.should eq(0x04034b50) # Signature
      br.read_2b.should eq(20)         # Version needed to extract
      br.read_2b.should eq(12)         # gp flags
      br.read_2b.should eq(8)          # storage mode
      br.read_2b.should eq(28_160)     # DOS time
      br.read_2b.should eq(18_673)     # DOS date
      br.read_4b.should eq(456)        # CRC32
      br.read_4b.should eq(768)        # compressed size
      br.read_4b.should eq(901)        # uncompressed size
      br.read_2b.should eq(7)          # filename size
      br.read_2b.should eq(9)          # extra fields size

      br.read_string_of(7).should eq("foo.bin") # extra fields size

      br.read_2b.should eq(0x5455) # Extended timestamp extra tag
      br.read_2b.should eq(5)      # Size of the timestamp extra
      br.read_1b.should eq(128)    # The timestamp flag

      ext_mtime = br.read_4b_signed
      ext_mtime.should eq(1_468_763_280) # The mtime encoded as a 4byte uint

      parsed_time = Time.unix(ext_mtime)
      parsed_time.year.should eq(2_016)
    end

    it "writes the local file header for an entry that does require Zip64 based \
        on uncompressed size (with the Zip64 extra)" do
      buf = IO::Memory.new
      mtime = Time.utc(2016, 7, 17, 13, 48)

      ZipTricks::Writer.new.write_local_file_header(io: buf,
        filename: "foo.bin",
        gp_flags: 12,
        crc32: 456,
        compressed_size: 768,
        uncompressed_size: (0xFFFFFFFF + 1),
        mtime: mtime,
        storage_mode: 8)

      br = ByteReader.new(buf)
      br.read_4b.should eq(0x04034b50)          # Signature
      br.read_2b.should eq(45)                  # Version needed to extract
      br.read_2b.should eq(12)                  # gp flags
      br.read_2b.should eq(8)                   # storage mode
      br.read_2b.should eq(28_160)              # DOS time
      br.read_2b.should eq(18_673)              # DOS date
      br.read_4b.should eq(456)                 # CRC32
      br.read_4b.should eq(0xFFFFFFFF)          # compressed size
      br.read_4b.should eq(0xFFFFFFFF)          # uncompressed size
      br.read_2b.should eq(7)                   # filename size
      br.read_2b.should eq(29)                  # extra fields size (Zip64 + extended timestamp)
      br.read_string_of(7).should eq("foo.bin") # extra fields size

      #  buf.should_not be_eof

      br.read_2b.should eq(1)              # Zip64 extra tag
      br.read_2b.should eq(16)             # Size of the Zip64 extra payload
      br.read_8b.should eq(0xFFFFFFFF + 1) # uncompressed size
      br.read_8b.should eq(768)            # compressed size
    end

    it "writes the local file header for an entry that does require Zip64 based \
        on compressed size (with the Zip64 extra)" do
      buf = IO::Memory.new
      mtime = Time.utc(2016, 7, 17, 13, 48)

      ZipTricks::Writer.new.write_local_file_header(io: buf,
        gp_flags: 12,
        crc32: 456,
        compressed_size: 0xFFFFFFFF + 1,
        uncompressed_size: 768,
        mtime: mtime,
        filename: "foo.bin",
        storage_mode: 8)

      br = ByteReader.new(buf)
      br.read_4b.should eq(0x04034b50)          # Signature
      br.read_2b.should eq(45)                  # Version needed to extract
      br.read_2b.should eq(12)                  # gp flags
      br.read_2b.should eq(8)                   # storage mode
      br.read_2b.should eq(28_160)              # DOS time
      br.read_2b.should eq(18_673)              # DOS date
      br.read_4b.should eq(456)                 # CRC32
      br.read_4b.should eq(0xFFFFFFFF)          # compressed size
      br.read_4b.should eq(0xFFFFFFFF)          # uncompressed size
      br.read_2b.should eq(7)                   # filename size
      br.read_2b.should eq(29)                  # extra fields size
      br.read_string_of(7).should eq("foo.bin") # extra fields size

      #  buf.should_not be_eof

      br.read_2b.should eq(1)              # Zip64 extra tag
      br.read_2b.should eq(16)             # Size of the Zip64 extra payload
      br.read_8b.should eq(768)            # uncompressed size
      br.read_8b.should eq(0xFFFFFFFF + 1) # compressed size
    end
  end

  describe "#write_data_descriptor" do
    it "writes 4-byte sizes into the data descriptor for standard file sizes" do
      buf = IO::Memory.new

      ZipTricks::Writer.new.write_data_descriptor(io: buf, crc32: 123, compressed_size: 89_821, uncompressed_size: 990_912)

      br = ByteReader.new(buf)
      br.read_4b.should eq(0x08074b50) # Signature
      br.read_4b.should eq(123)        # CRC32
      br.read_4b.should eq(89_821)     # compressed size
      br.read_4b.should eq(990_912)    # uncompressed size
      #   buf.should be_eof
    end

    it "writes 8-byte sizes into the data descriptor for Zip64 compressed file size" do
      buf = IO::Memory.new

      ZipTricks::Writer.new.write_data_descriptor(io: buf,
        crc32: 123,
        compressed_size: (0xFFFFFFFF + 1),
        uncompressed_size: 990_912)

      br = ByteReader.new(buf)
      br.read_4b.should eq(0x08074b50)     # Signature
      br.read_4b.should eq(123)            # CRC32
      br.read_8b.should eq(0xFFFFFFFF + 1) # compressed size
      br.read_8b.should eq(990_912)        # uncompressed size
      # buf.should be_eof
    end

    it "writes 8-byte sizes into the data descriptor for Zip64 uncompressed file size" do
      buf = IO::Memory.new

      ZipTricks::Writer.new.write_data_descriptor(io: buf,
        crc32: 123,
        compressed_size: 123,
        uncompressed_size: 0xFFFFFFFF + 1)

      br = ByteReader.new(buf)
      br.read_4b.should eq(0x08074b50)     # Signature
      br.read_4b.should eq(123)            # CRC32
      br.read_8b.should eq(123)            # compressed size
      br.read_8b.should eq(0xFFFFFFFF + 1) # uncompressed size
      #  buf.should be_eof
    end
  end

  describe "#write_central_directory_file_header" do
    it "writes the file header for a small-ish entry" do
      buf = IO::Memory.new

      ZipTricks::Writer.new.write_central_directory_file_header(io: buf,
        local_file_header_location: 898_921,
        gp_flags: 555,
        storage_mode: 23,
        compressed_size: 901,
        uncompressed_size: 909_102,
        mtime: Time.utc(2016, 2, 2, 14, 0),
        crc32: 89_765,
        filename: "a-file.txt")

      br = ByteReader.new(buf)
      br.read_4b.should eq(0x02014b50) # Central directory entry sig
      br.read_2b.should eq(820)        # version made by
      br.read_2b.should eq(20)         # version need to extract
      br.read_2b.should eq(555)        # general purpose bit flag (explicitly
      # set to bogus value to ensure we pass it through)
      br.read_2b.should eq(23)      # compression method (explicitly set to bogus value)
      br.read_2b.should eq(28_672)  # last mod file time
      br.read_2b.should eq(18_498)  # last mod file date
      br.read_4b.should eq(89_765)  # crc32
      br.read_4b.should eq(901)     # compressed size
      br.read_4b.should eq(909_102) # uncompressed size
      br.read_2b.should eq(10)      # filename length
      br.read_2b.should eq(9)       # extra field length
      br.read_2b.should eq(0)       # file comment
      br.read_2b.should eq(0)       # disk number, must be blanked to the
      # maximum value because of The Unarchiver bug
      br.read_2b.should eq(0)                       # internal file attributes
      br.read_4b.should eq(2_175_008_768)           # external file attributes
      br.read_4b.should eq(898_921)                 # relative offset of local header
      br.read_string_of(10).should eq("a-file.txt") # the filename
    end

    it "writes the file header for an entry that contains an empty directory" do
      buf = IO::Memory.new

      ZipTricks::Writer.new.write_central_directory_file_header(io: buf,
        local_file_header_location: 898_921,
        gp_flags: 555,
        storage_mode: 23,
        compressed_size: 0,
        uncompressed_size: 0,
        mtime: Time.utc(2016, 2, 2, 14, 0),
        crc32: 544,
        filename: "this-is-here-directory/")

      br = ByteReader.new(buf)
      br.read_4b.should eq(0x02014b50) # Central directory entry sig
      br.read_2b.should eq(820)        # version made by
      br.read_2b.should eq(20)         # version need to extract
      br.read_2b.should eq(555)        # general purpose bit flag (explicitly
      # set to bogus value to ensure we pass it through)
      br.read_2b.should eq(23)                                   # compression method (explicitly set to bogus value)
      br.read_2b.should eq(28_672)                               # last mod file time
      br.read_2b.should eq(18_498)                               # last mod file date
      br.read_4b.should eq(544)                                  # crc32
      br.read_4b.should eq(0)                                    # compressed size
      br.read_4b.should eq(0)                                    # uncompressed size
      br.read_2b.should eq(23)                                   # filename length
      br.read_2b.should eq(9)                                    # extra field length
      br.read_2b.should eq(0)                                    # file comment
      br.read_2b.should eq(0)                                    # disk number (0, first disk)
      br.read_2b.should eq(0)                                    # internal file attributes
      br.read_4b.should eq(1_106_051_072)                        # external file attributes
      br.read_4b.should eq(898_921)                              # relative offset of local header
      br.read_string_of(23).should eq("this-is-here-directory/") # the filename
    end

    it "writes the file header for an entry that requires Zip64 extra because of \
        the uncompressed size" do
      buf = IO::Memory.new

      ZipTricks::Writer.new.write_central_directory_file_header(io: buf,
        local_file_header_location: 898_921,
        gp_flags: 555,
        storage_mode: 23,
        compressed_size: 901,
        uncompressed_size: 0xFFFFFFFFF + 3,
        mtime: Time.utc(2016, 2, 2, 14, 0),
        crc32: 89_765,
        filename: "a-file.txt")

      br = ByteReader.new(buf)
      br.read_4b.should eq(0x02014b50) # Central directory entry sig
      br.read_2b.should eq(820)        # version made by
      br.read_2b.should eq(45)         # version need to extract
      br.read_2b.should eq(555)        # general purpose bit flag
      # (explicitly set to bogus value
      # to ensure we pass it through)
      br.read_2b.should eq(23) # compression method (explicitly
      # set to bogus value)
      br.read_2b.should eq(28_672)                  # last mod file time
      br.read_2b.should eq(18_498)                  # last mod file date
      br.read_4b.should eq(89_765)                  # crc32
      br.read_4b.should eq(0xFFFFFFFF)              # compressed size
      br.read_4b.should eq(0xFFFFFFFF)              # uncompressed size
      br.read_2b.should eq(10)                      # filename length
      br.read_2b.should eq(41)                      # extra field length
      br.read_2b.should eq(0)                       # file comment
      br.read_2b.should eq(0xFFFF)                  # disk number, must be blanked to the maximum value
      br.read_2b.should eq(0)                       # internal file attributes
      br.read_4b.should eq(2_175_008_768)           # external file attributes
      br.read_4b.should eq(0xFFFFFFFF)              # relative offset of local header
      br.read_string_of(10).should eq("a-file.txt") # the filename

      br.read_2b.should eq(1)               # Zip64 extra tag
      br.read_2b.should eq(28)              # Size of the Zip64 extra payload
      br.read_8b.should eq(0xFFFFFFFFF + 3) # uncompressed size
      br.read_8b.should eq(901)             # compressed size
      br.read_8b.should eq(898_921)         # local file header location
    end

    it "writes the file header for an entry that requires Zip64 extra because of \
        the compressed size" do
      buf = IO::Memory.new

      ZipTricks::Writer.new.write_central_directory_file_header(io: buf,
        local_file_header_location: 898_921,
        gp_flags: 555,
        storage_mode: 23,
        compressed_size: 0xFFFFFFFFF + 3,
        # the worst compression scheme in the universe
        uncompressed_size: 901,
        mtime: Time.utc(2016, 2, 2, 14, 0),
        crc32: 89_765,
        filename: "a-file.txt")

      br = ByteReader.new(buf)
      br.read_4b.should eq(0x02014b50) # Central directory entry sig
      br.read_2b.should eq(820)        # version made by
      br.read_2b.should eq(45)         # version need to extract
      br.read_2b.should eq(555)        # general purpose bit flag (explicitly
      # set to bogus value to ensure we pass it through)
      br.read_2b.should eq(23)         # compression method (explicitly set to bogus value)
      br.read_2b.should eq(28_672)     # last mod file time
      br.read_2b.should eq(18_498)     # last mod file date
      br.read_4b.should eq(89_765)     # crc32
      br.read_4b.should eq(0xFFFFFFFF) # compressed size
      br.read_4b.should eq(0xFFFFFFFF) # uncompressed size
      br.read_2b.should eq(10)         # filename length
      br.read_2b.should eq(41)         # extra field length
      br.read_2b.should eq(0)          # file comment
      br.read_2b.should eq(0xFFFF)     # disk number, must be blanked to the
      # maximum value because of The Unarchiver bug
      br.read_2b.should eq(0)                       # internal file attributes
      br.read_4b.should eq(2_175_008_768)           # external file attributes
      br.read_4b.should eq(0xFFFFFFFF)              # relative offset of local header
      br.read_string_of(10).should eq("a-file.txt") # the filename

      #  buf.should_not be_eof
      br.read_2b.should eq(1)               # Zip64 extra tag
      br.read_2b.should eq(28)              # Size of the Zip64 extra payload
      br.read_8b.should eq(901)             # uncompressed size
      br.read_8b.should eq(0xFFFFFFFFF + 3) # compressed size
      br.read_8b.should eq(898_921)         # local file header location
    end

    it "writes the file header for an entry that requires Zip64 extra because of \
        the local file header offset being beyound 4GB" do
      buf = IO::Memory.new

      ZipTricks::Writer.new.write_central_directory_file_header(io: buf,
        local_file_header_location: 0xFFFFFFFFF + 1,
        gp_flags: 555,
        storage_mode: 23,
        compressed_size: 8_981,
        # the worst compression scheme in the universe
        uncompressed_size: 819_891,
        mtime: Time.utc(2016, 2, 2, 14, 0),
        crc32: 89_765,
        filename: "a-file.txt")

      br = ByteReader.new(buf)
      br.read_4b.should eq(0x02014b50) # Central directory entry sig
      br.read_2b.should eq(820)        # version made by
      br.read_2b.should eq(45)         # version need to extract
      br.read_2b.should eq(555)        # general purpose bit flag (explicitly
      # set to bogus value to ensure we pass it through)
      br.read_2b.should eq(23)         # compression method (explicitly set to bogus value)
      br.read_2b.should eq(28_672)     # last mod file time
      br.read_2b.should eq(18_498)     # last mod file date
      br.read_4b.should eq(89_765)     # crc32
      br.read_4b.should eq(0xFFFFFFFF) # compressed size
      br.read_4b.should eq(0xFFFFFFFF) # uncompressed size
      br.read_2b.should eq(10)         # filename length
      br.read_2b.should eq(41)         # extra field length
      br.read_2b.should eq(0)          # file comment
      br.read_2b.should eq(0xFFFF)     # disk number, must be blanked to the
      # maximum value because of The Unarchiver bug
      br.read_2b.should eq(0)                       # internal file attributes
      br.read_4b.should eq(2_175_008_768)           # external file attributes
      br.read_4b.should eq(0xFFFFFFFF)              # relative offset of local header
      br.read_string_of(10).should eq("a-file.txt") # the filename

      #  buf.should_not be_eof
      br.read_2b.should eq(1)               # Zip64 extra tag
      br.read_2b.should eq(28)              # Size of the Zip64 extra payload
      br.read_8b.should eq(819_891)         # uncompressed size
      br.read_8b.should eq(8_981)           # compressed size
      br.read_8b.should eq(0xFFFFFFFFF + 1) # local file header location
    end
  end

  describe "#write_end_of_central_directory" do
    it "writes out the EOCD with all markers for a small ZIP file with just a few entries" do
      buf = IO::Memory.new

      num_files = rand(8..190)
      ZipTricks::Writer.new.write_end_of_central_directory(io: buf,
        start_of_central_directory_location: 9_091_211,
        central_directory_size: 9_091,
        num_files_in_archive: num_files, comment: "xyz")

      br = ByteReader.new(buf)
      br.read_4b.should eq(0x06054b50) # EOCD signature
      br.read_2b.should eq(0)          # number of this disk
      br.read_2b.should eq(0)          # number of the disk with the EOCD record
      br.read_2b.should eq(num_files)  # number of files on this disk
      br.read_2b.should eq(num_files)  # number of files in central directory
      # total (for all disks)
      br.read_4b.should eq(9_091)     # size of the central directory (cdir records for all files)
      br.read_4b.should eq(9_091_211) # start of central directory offset from
      # the beginning of file/disk

      comment_length = br.read_2b
      comment_length.should eq(3)

      br.read_string_of(comment_length).should match(/xyz/)
    end

    it "writes out the custom comment" do
      buf = IO::Memory.new
      comment = "Ohai mate"
      ZipTricks::Writer.new.write_end_of_central_directory(io: buf,
        start_of_central_directory_location: 9_091_211,
        central_directory_size: 9_091,
        num_files_in_archive: 4,
        comment: comment)
      #
      #      size_and_comment = buf[((comment.bytesize + 2) * -1)..-1]
      #      comment_size = size_and_comment.unpack("v")[0]
      #      comment_size.should eq(comment.bytesize)
    end

    it "writes out the Zip64 EOCD as well if the central directory is located \
        beyound 4GB in the archive" do
      buf = IO::Memory.new

      num_files = rand(8..190)
      ZipTricks::Writer.new.write_end_of_central_directory(io: buf,
        start_of_central_directory_location: 0xFFFFFFFF + 3,
        central_directory_size: 9091,
        num_files_in_archive: num_files)

      br = ByteReader.new(buf)

      br.read_4b.should eq(0x06064b50) # Zip64 EOCD signature
      br.read_8b.should eq(44)         # Zip64 EOCD record size
      br.read_2b.should eq(820)        # Version made by
      br.read_2b.should eq(45)         # Version needed to extract
      br.read_4b.should eq(0)          # Number of this disk
      br.read_4b.should eq(0)          # Number of the disk with the Zip64 EOCD record
      br.read_8b.should eq(num_files)  # Number of entries in the central
      # directory of this disk
      br.read_8b.should eq(num_files) # Number of entries in the central
      # directories of all disks
      br.read_8b.should eq(9_091)          # Central directory size
      br.read_8b.should eq(0xFFFFFFFF + 3) # Start of central directory location

      br.read_4b.should eq(0x07064b50)               # Zip64 EOCD locator signature
      br.read_4b.should eq(0)                        # Number of the disk with the EOCD locator signature
      br.read_8b.should eq((0xFFFFFFFF + 3) + 9_091) # Where the Zip64 EOCD record starts
      br.read_4b.should eq(1)                        # Total number of disks

      # Then the usual EOCD record
      br.read_4b.should eq(0x06054b50) # EOCD signature
      br.read_2b.should eq(0)          # number of this disk
      br.read_2b.should eq(0)          # number of the disk with the EOCD record
      br.read_2b.should eq(0xFFFF)     # number of files on this disk
      br.read_2b.should eq(0xFFFF)     # number of files in central directory
      # total (for all disks)
      br.read_4b.should eq(0xFFFFFFFF) # size of the central directory
      # (cdir records for all files)
      br.read_4b.should eq(0xFFFFFFFF) # start of central directory offset
      # from the beginning of file/disk

      comment_length = br.read_2b
      comment_length.should_not eq(0)

      br.read_string_of(comment_length).should match(/zip_tricks/i)
    end

    it "writes out the Zip64 EOCD if the archive has more than 0xFFFF files" do
      buf = IO::Memory.new

      ZipTricks::Writer.new.write_end_of_central_directory(io: buf,
        start_of_central_directory_location: 123,
        central_directory_size: 9_091,
        num_files_in_archive: 0xFFFF + 1, comment: "")

      br = ByteReader.new(buf)

      br.read_4b.should eq(0x06064b50) # Zip64 EOCD signature
      br.read_8b
      br.read_2b
      br.read_2b
      br.read_4b
      br.read_4b
      br.read_8b.should eq(0xFFFF + 1) # Number of entries in the central
      # directory of this disk
      br.read_8b.should eq(0xFFFF + 1) # Number of entries in the central
      # directories of all disks
    end

    it "writes out the Zip64 EOCD if the central directory size exceeds 0xFFFFFFFF" do
      buf = IO::Memory.new

      ZipTricks::Writer.new.write_end_of_central_directory(io: buf,
        start_of_central_directory_location: 123,
        central_directory_size: 0xFFFFFFFF + 2,
        num_files_in_archive: 5, comment: "Foooo")

      br = ByteReader.new(buf)

      br.read_4b.should eq(0x06064b50) # Zip64 EOCD signature
      br.read_8b
      br.read_2b
      br.read_2b
      br.read_4b
      br.read_4b
      br.read_8b.should eq(5) # Number of entries in the central directory of this disk
      br.read_8b.should eq(5) # Number of entries in the central directories of all disks
    end
  end
end
