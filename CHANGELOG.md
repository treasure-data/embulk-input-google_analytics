## 0.1.20 - 2019-04-01
* Fix **(ArgumentError) no time information in ""** when last_record_time is null [#42](https://github.com/treasure-data/embulk-input-google_analytics/pull/42)

## 0.1.19 - 2018-10-03
* Make it easy to understand error message of Google Analytics connector

## 0.1.18 - 2018-05-23
* Suport User Account Authentication [#33](https://github.com/treasure-data/embulk-input-google_analytics/pull/33)
* Ignore last_record_time if non-incremental task [#34](https://github.com/treasure-data/embulk-input-google_analytics/pull/34)

## 0.1.17 - 2018-04-16

* Add more descriptive error message when Google API return invalid time format [#32](https://github.com/treasure-data/embulk-input-google_analytics/pull/32)

## 0.1.16 - 2018-02-06

* Use user profile timezone when format next from_date [#31](https://github.com/treasure-data/embulk-input-google_analytics/pull/31)


## 0.1.15 - 2017-11-29

* Add explicit logging for the number of skipped records [#30](https://github.com/treasure-data/embulk-input-google_analytics/pull/30)

## 0.1.14 - 2017-06-27

* Fixed version of google-api-client [#26](https://github.com/treasure-data/embulk-input-google_analytics/pull/26)

## 0.1.13 - 2017-03-28
* Fixed bug `last_record_time` in `preview` mode [#20](https://github.com/treasure-data/embulk-input-google_analytics/pull/20)

## 0.1.12 - 2017-01-31
* Support 'fooXXbar' column names [#19](https://github.com/treasure-data/embulk-input-google_analytics/pull/19)

## 0.1.11 - 2017-01-16
* Throw DataError if '(other)' values appear as ga:dateHour as ga:date or ga:dateHour [#18](https://github.com/treasure-data/embulk-input-google_analytics/pull/18)

## 0.1.10 - 2016-12-08
* Logging unexpected time string [#17](https://github.com/treasure-data/embulk-input-google_analytics/pull/17)

## 0.1.9 - 2016-11-22
* Support 'foobarXX' column names [#16](https://github.com/treasure-data/embulk-input-google_analytics/pull/16)

## 0.1.8 - 2016-11-09
* TIME column should be double, not timestamp. e.g. sessionDuration (thx @kazuya030) [#13](https://github.com/treasure-data/embulk-input-google_analytics/pull/13) [#15](https://github.com/treasure-data/embulk-input-google_analytics/pull/15)

## 0.1.7 - 2016-10-20
* Fix to generate `end_date` on config_diff  [#12](https://github.com/treasure-data/embulk-input-google_analytics/pull/12)

## 0.1.6 - 2016-08-29
* Add no-op guessing to avoid guess error [#11](https://github.com/treasure-data/embulk-input-google_analytics/pull/11)

## 0.1.5 - 2016-08-23
* Enable custom dimensions [#10](https://github.com/treasure-data/embulk-input-google_analytics/pull/10)

## 0.1.4 - 2016-08-19
* Always add `view_id` into records [#9](https://github.com/treasure-data/embulk-input-google_analytics/pull/9)

## 0.1.3 - 2016-08-15
* Use net/http to avoid TLS error [#8](https://github.com/treasure-data/embulk-input-google_analytics/pull/8)

## 0.1.2 - 2016-07-13

* Fix when `end_date` is nil [#7](https://github.com/treasure-data/embulk-input-google_analytics/pull/7)

## 0.1.1 - 2016-07-13
* Enable scheduled execution [#4](https://github.com/treasure-data/embulk-input-google_analytics/pull/4)
* Error handling [#6](https://github.com/treasure-data/embulk-input-google_analytics/pull/6)
* Ignore too early accessing data due to it is not fixed value [#5](https://github.com/treasure-data/embulk-input-google_analytics/pull/5)

## 0.1.0 - 2016-07-07

The first release!!
