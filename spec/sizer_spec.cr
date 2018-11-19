require "./spec_helper"

describe ZipTricks::Sizer do
  describe ".size" do
    it "sizes the archive with all sorts of entries" do
      size = ZipTricks::Sizer.size do |s|
        s.predeclare_entry(filename: "deflated1.txt", uncompressed_size: 8969887, compressed_size: 1245, use_data_descriptor: true)
        s.predeclare_entry(filename: "deflated12.txt", uncompressed_size: 4568, compressed_size: 4065, use_data_descriptor: true)
      end
      size.should eq(5641)
    end

    it "sizes an empty archive" do
      size = ZipTricks::Sizer.size do |s|
      end
      size.should eq(57)
    end
  end
end
