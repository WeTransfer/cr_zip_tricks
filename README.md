# cr_zip_tricks

[![Crystal CI](https://github.com/WeTransfer/cr_zip_tricks/actions/workflows/crystal.yml/badge.svg)](https://github.com/WeTransfer/cr_zip_tricks/actions/workflows/crystal.yml)

An alternate ZIP writer for Crystal, ported from [zip_tricks for Ruby](https://github.com/WeTransfer/zip_tricks)

## Installation

1. Add the dependency to your `shard.yml`:
```yaml
dependencies:
  cr_zip_tricks:
    github: WeTransfer/cr_zip_tricks
```
2. Run `shards install`

## Usage

Archiving to any IO:

```crystal
require "zip_tricks"

ZipTricks::Streamer.archive(STDOUT) do |s|
  s.add_deflated("deflated.txt") do |sink|
    sink << "Hello stranger! This is a chunk of text that is going to compress. Well."
  end

  s.add_stored("stored.txt") do |sink|
    sink << "Goodbye stranger!"
  end
end

```

Sizing an archive before creation, to the byte:

```crystal
require "cr_zip_tricks"

size = ZipTricks::Sizer.size do |s|
  s.predeclare_entry(filename: "deflated1.txt", uncompressed_size: 8969887, compressed_size: 1245, use_data_descriptor: true)
  s.predeclare_entry(filename: "deflated2.txt", uncompressed_size: 4568, compressed_size: 4065, use_data_descriptor: true)
end
size #=> 5641
```

## Using it with Kemal or other web app skeleton

Here is a Kemal app that outputs itself, 1000 times, compressed:

```crystal
require "kemal"
require "cr_zip_tricks"

get "/quine.zip" do |env|
  env.response.headers["Content-Type"] = "application/octet-stream"
  env.response.headers["Content-Disposition"] = "attachment"
  ZipTricks::Streamer.archive(env.response) do |s|
    1000.times do |i|
      s.add_deflated("cr_download_server_%05d.cr" % i) do |sink|
        File.open(__FILE__, "rb") do |f|
          IO.copy(f, sink)
        end
      end
    end
  end
end

Kemal.run
```

## Development

TODO: Write development instructions here

## Contributing

1. Fork it (<https://github.com/WeTransfer/cr_zip_tricks/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Julik Tarkhanov](https://github.com/julik) - creator and maintainer
