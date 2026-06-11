-- =============================================================================
-- analysis/run_study_analysis/scripts/sql/int_intake_responses_scored.sql
--
-- Transforms and stores the raw intake survey responses from the real study.
-- Source: dkg-phd-thesis.qualtrics.stg_intake_responses
--
-- Scale UDFs:
-- likert_to_int_freq     -- frequency scale (PA, NA): Never...Always
-- likert_to_int_agree    -- agreement scale (BR, VIO, JS, JIS, DES):
-- Strongly disagree...Strongly agree (Somewhat variants)
--
-- Additions vs synthetic:
-- jis1          -- Job Insecurity Scale (JIS); agreement scale
-- des1, des2    -- Desirability of Movement (DES); agreement scale
-- recruitment_source -- CloudResearch vs snowball derived from connect_id
-- =============================================================================
create temp function to_bool(val string)
as (val = 'Yes')
;

create temp function to_iana_tz(val string)
as
    (
        case
            val
            when 'US/Eastern'
            then 'America/New_York'
            when 'US/Central'
            then 'America/Chicago'
            when 'US/Mountain'
            then 'America/Denver'
            when 'US/Pacific'
            then 'America/Los_Angeles'
            when 'US/Alaska'
            then 'America/Anchorage'
            when 'US/Hawaii'
            then 'Pacific/Honolulu'
            when 'US/Samoa'
            then 'Pacific/Pago_Pago'
        end
    )
;

-- Frequency scale: PA and NA items (Never / Rather infrequently / Some of the time /
-- Quite often / Always)
create temp function likert_to_int_freq(val string)
as
    (
        case
            val
            when 'Never'
            then 1
            when 'Rather infrequently'
            then 2
            when 'Some of the time'
            then 3
            when 'Quite often'
            then 4
            when 'Always'
            then 5
        end
    )
;

-- Agreement scale: BR, VIO, JS, JIS, DES items
-- "Disagree" (without "Somewhat") is treated as 2, matching "Somewhat disagree".
-- It appears only in br and js1; all other agreement items use "Somewhat disagree".
create temp function likert_to_int_agree(val string)
as
    (
        case
            val
            when 'Strongly disagree'
            then 1
            when 'Disagree'
            then 2
            when 'Somewhat disagree'
            then 2
            when 'Neither agree nor disagree'
            then 3
            when 'Somewhat agree'
            then 4
            when 'Strongly agree'
            then 5
        end
    )
;

create or replace table `dkg-phd-thesis.qualtrics.int_intake_responses_scored` as
with
    transformed as (
        select
            response_id,
            survey_id,
            _created_at,
            duration,
            to_bool (consent) as has_consented,
            connect_id,
            -- CloudResearch connect_id = exactly 32 alphanumeric chars; snowball respondents entered random text
            regexp_contains(coalesce(connect_id, ''), r'^[A-Za-z0-9]{32}$') as has_connect_id,
            case
                when regexp_contains(connect_id, r'^[A-Za-z0-9]{32}$') then 'cloudresearch'
                else 'snowball'
            end as recruitment_source,
            to_bool (age_flag) as is_adult,
            to_bool (location_flag) as is_domestic,
            to_bool (language_flag) as is_english_proficient,
            safe_cast(phone as int64) as phone_number,
            to_iana_tz (timezone) as time_zone,
            date(selected_date) as followup_date,
            age,
            ethnicity,
            gender_identity as gender,
            job_tenure,
            education_level as edu_lvl,
            to_bool (remote_flag) as is_remote,
            work_classification,
            work_shift,
            -- PA items (frequency scale)
            likert_to_int_freq (pa1) as pa1,
            likert_to_int_freq (pa2) as pa2,
            likert_to_int_freq (pa3) as pa3,
            likert_to_int_freq (pa4) as pa4,
            likert_to_int_freq (pa5) as pa5,
            -- NA items (frequency scale)
            likert_to_int_freq (na1) as na1,
            likert_to_int_freq (na2) as na2,
            likert_to_int_freq (na3) as na3,
            likert_to_int_freq (na4) as na4,
            likert_to_int_freq (na5) as na5,
            -- BR items (agreement scale)
            likert_to_int_agree (br1) as br1,
            likert_to_int_agree (br2) as br2,
            likert_to_int_agree (br3) as br3,
            likert_to_int_agree (br4) as br4,
            likert_to_int_agree (br5) as br5,
            -- VIO items (agreement scale)
            likert_to_int_agree (vio1) as vio1,
            likert_to_int_agree (vio2) as vio2,
            likert_to_int_agree (vio3) as vio3,
            likert_to_int_agree (vio4) as vio4,
            -- JS (single item; agreement scale)
            likert_to_int_agree (js1) as js1,
            -- JIS (single item; agreement scale)
            likert_to_int_agree (jis1) as jis1,
            -- DES items (agreement scale)
            likert_to_int_agree (des1) as des1,
            likert_to_int_agree (des2) as des2
        from
            `dkg-phd-thesis.qualtrics.stg_intake_responses`
    )
select
    *,
    -- means
    ieee_divide(pa1 + pa2 + pa3 + pa4 + pa5, 5) as pa_mean,
    ieee_divide(na1 + na2 + na3 + na4 + na5, 5) as na_mean,
    ieee_divide(br1 + br2 + br3 + br4 + br5, 5) as br_mean,
    ieee_divide(vio1 + vio2 + vio3 + vio4, 4) as vio_mean,
    js1 as js_mean,
    jis1 as jis_mean,
    ieee_divide(des1 + des2, 2) as des_mean,
    -- sums
    pa1 + pa2 + pa3 + pa4 + pa5 as pa_sum,
    na1 + na2 + na3 + na4 + na5 as na_sum,
    br1 + br2 + br3 + br4 + br5 as br_sum,
    vio1 + vio2 + vio3 + vio4 as vio_sum,
    js1 as js_sum,
    jis1 as jis_sum,
    des1 + des2 as des_sum
from
    transformed
;
