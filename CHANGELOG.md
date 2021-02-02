# Changelog

## v0.1.3

* New features
  * New `RetryConfig` param: `worst_case_download_speed`. This makes it
    possible to match the timeout to the download size and fail before `max_timeout`.
  * `max_timeout` is now 24 hours to match the NervesHub download URL validity time.
    Now downloads can survive multi-hour network outages without starting over.

## v0.1.2

* Bug Fixes
  * Fix issue where query parameters were not being encoded correctly

## v0.1.1

* Retired due to typo

## v0.1.0

* Initial Release
