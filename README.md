# cr_zip_tricks

An alternate ZIP writer for Crystal, ported from [zip_tricks for Ruby](https://github.com/WeTransfer/zip_tricks)

## Installation

1. Add the dependency to your `shard.yml`:
```yaml
dependencies:
  zip_tricks:
    github: WeTransfer/zip_tricks
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
require "zip_tricks"

size = ZipTricks::Sizer.size do |s|
  s.predeclare_entry(filename: "deflated1.txt", uncompressed_size: 8969887, compressed_size: 1245, use_data_descriptor: true)
  s.predeclare_entry(filename: "deflated2.txt", uncompressed_size: 4568, compressed_size: 4065, use_data_descriptor: true)
end
size #=> 5641
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
