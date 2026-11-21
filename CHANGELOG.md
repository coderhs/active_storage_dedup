## [Unreleased]

- Add `config.logger` to route gem output to a custom logger or silence it (#1)
- Resolve the default logger on each call so a replaced `Rails.logger` is picked up

## [1.0.0.beta] - 2025-12-01

- Enforce minimum support of Rails 7.2 and Ruby 3.1+ (`22910a5`)
- Limit compatibility to officially supported Rails/Ruby versions (`e8c1391`)
- Default the test run to specs only for faster feedback (`398b015`)
- Expand CI matrix to cover all current Rails and Ruby releases (`16d90c9`)
- Polish specs and linting (`716c0ff`, `7f1c556`)
- Link the sample test application in docs (`62fcc33`)

## [1.0.0.alpha] - 2025-11-23

- Initial release
