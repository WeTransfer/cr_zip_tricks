# crzt

TODO: Write a description here

## Installation

1. Add the dependency to your `shard.yml`:
```yaml
dependencies:
  crzt:
    github: julik/crzt
```
2. Run `shards install`

## Usage

```crystal
require "crzt"

Crzt::Streamer.new(STDOUT) do |s|
  s.add_deflated("deflated.txt") do |sink|
    sink << "Hello stranger! This is a chunk of text that is going to compress. Well."
  end

  s.add_stored("stored.txt") do |sink|
    sink << "Goodbye stranger!"
  end
end

```

## Development

TODO: Write development instructions here

## Contributing

1. Fork it (<https://github.com/julik/crzt/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Julik Tarkhanov](https://github.com/julik) - creator and maintainer
