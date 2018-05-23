[![CircleCI](https://circleci.com/gh/treasure-data/embulk-input-google_analytics/tree/master.svg?style=svg)](https://circleci.com/gh/treasure-data/embulk-input-google_analytics/tree/master)
[![Code Climate](https://codeclimate.com/github/treasure-data/embulk-input-google_analytics/badges/gpa.svg)](https://codeclimate.com/github/treasure-data/embulk-input-google_analytics)
[![Test Coverage](https://codeclimate.com/github/treasure-data/embulk-input-google_analytics/badges/coverage.svg)](https://codeclimate.com/github/treasure-data/embulk-input-google_analytics/coverage)
[![Issue Count](https://codeclimate.com/github/treasure-data/embulk-input-google_analytics/badges/issue_count.svg)](https://codeclimate.com/github/treasure-data/embulk-input-google_analytics)
[![Gem Version](https://badge.fury.io/rb/embulk-input-google_analytics.svg)](https://badge.fury.io/rb/embulk-input-google_analytics)

# Google Analytics input plugin for Embulk

Embulk input plugin for Google Analytics reports.

## Configuration

- **json_key_content**: See example config.
- **view_id**: View ID for target data. See [Get View ID](#get-view-id) (string, required)
- **time_series**: Only `ga:dateHour` or `ga:date` (string, required)
- **dimensions**: Target dimensions (array, default: `[]` )
- **metrics**: Target metrics (array, default: `[]` )
- **start_date**: Target report start date. Valid format is "YYYY-MM-DD". (string, default: [7 days ago](https://developers.google.com/analytics/devguides/reporting/core/v4/rest/v4/reports/batchGet#reportrequest))
- **end_date**: Target report end date. Valid format is "YYYY-MM-DD". (string, default: [1 day ago](https://developers.google.com/analytics/devguides/reporting/core/v4/rest/v4/reports/batchGet#reportrequest))
- **incremental**: `true` for generate "config_diff" with `embulk run -c config.diff` (bool, default: true)
- **last_record_time**: Ignore fetched records until this time. Mainly for incremental:true. (string, default: nil)
- **retry_limit**: Try to retry this times (integer, default: 5)
- **retry_initial_wait_sec**: Wait seconds for exponential backoff initial value (integer, default: 2)

### **New update from verions  0.1.18**
Started from version 0.1.18, the Plugin also supports User Account Authentication along with Service Account Authentication see: [OAuth 2.0 for Server-side Web Application](https://developers.google.com/identity/protocols/OAuth2WebServer). Extra optional configuration keys ware added and the **json_key_content** is made optional 
 - **client_id**: client_id for application (string, optional)
 - **client_secret**: client_secret for application (string, optional)
 - **refresh_token**: the refresh_token optained during exchange an authentication code (string, optional)

### Get View ID

1. Go to the [Google Analytics sign in page](https://analytics.google.com/analytics/) and sign in.
1. Click "Admin" tab at left below
1. Select the "Property" using the drop-down menu below ‘Property’.
1. Select ‘View Settings’ beneath ‘View’.
1. The View ID for the selected property is listed first under ‘Basic Settings

### About `json_key_content` option.

You need a service account on Google.

<ol>
  <li>Open the <a href="https://console.developers.google.com/permissions/serviceaccounts"><b>Service accounts</b> page</a>. If prompted,
select a project.</li>
  <li>Click <b>Create service account</b>.</li>
  <li>
    
    In the <b>Create service account</b> window, type a name for the service
    account, and select <b>Furnish a new private key</b>. If you want to
    <a href="https://developers.google.com/identity/protocols/OAuth2ServiceAccount#delegatingauthority">grant
    Google Apps domain-wide authority</a> to the service account, also select
    <b>Enable Google Apps Domain-wide Delegation</b>.
    
    Then click <b>Create</b>.</li>
</ol>
From: <https://developers.google.com/identity/protocols/OAuth2ServiceAccount>

Screenshot: ![Service Account](./service_account.png)

## Why the result doesn't match with web interface?

Google Reporting API uses "sampling" data.

- https://developers.google.com/analytics/devguides/reporting/core/v4/basics#sampling
- https://support.google.com/analytics/answer/2637192

That means sometimes result will be unmatched with Google Analytics web interface, and the result is based on sampled data, not all of raw data. This is a Google API's limitation.

Currently a sampling level supported by this plugin is DEFAULT only. Let us know if you want to use other sampling level (SMALL or LARGE).

## Example

```yaml
in:
  type: google_analytics
  json_key_content: |
    {
      "type": "service_account",
      "project_id": "....",
      "private_key_id": "....",
      "private_key": "-----BEGIN PRIVATE KEY-----\n..........................\n-----END PRIVATE KEY-----\n",
      "client_email": ".....",
      "client_id": ".........",
      "auth_uri": "https://accounts.google.com/o/oauth2/auth",
      "token_uri": "https://accounts.google.com/o/oauth2/token",
      "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
      "client_x509_cert_url": ".........."
    }
  view_id: 123111111
  time_series: "ga:dateHour" # hourly basis
 
  # https://developers.google.com/analytics/devguides/reporting/core/dimsmets
  dimensions:
    - "ga:browser"
  metrics:
    - "ga:visits"
    - "ga:pageviews"

  start_date: "2016-06-27"
  end_date: "2016-06-28"
```

## Config example using User Authentication
```yaml
 in:
  type: google_analytics
  client_id: "#############apps.googleusercontent.com"
  client_secret: "##############QLxgrfis4"
  refresh_token: "##########awWNT9lTeGq8weKE"
  view_id: 123111111
  time_series: "ga:dateHour" # hourly basis
  dimensions:
    - "ga:browser"
  metrics:
    - "ga:visits"
    - "ga:pageviews"

  start_date: "2016-06-27"
  end_date: "2016-06-28"
```

## Build

```
$ rake
```
