# Changelog

## v0.3.0

No breaking changes

This bumps `:fwup` dependency to 1.0.0 which opens up new features
during the update process. The default behavior remains unchanged

* New Features
  * Add support for setting fwup environment variables
  * Support changing the fwup upgrade task

## v0.2.0

This release has an API breaking change. You're probably using this library as a result of depending on `nerves_hub_link` so these changes won't affect your application code.

* New features
  * On reconnecting to a NervesHub instance, an firmware download that's in process will be reported
  
* Bug fixes
  * Properly ignore NervesHub responses that indicate no update is available.
  
* API breaking change:
  * `apply_update/1` now returns a `%NervesHubLinkCommon.Message.UpdateInfo{}`

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
