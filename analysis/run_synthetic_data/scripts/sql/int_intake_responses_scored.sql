-- =============================================================================
-- analysis/run_synthetic_data/scripts/sql/int_intake_responses_scored.sql
--
-- Transforms and stores the raw intake survey responses.
-- =============================================================================
create temp function to_bool (val string) as (val = 'Yes')
;

create temp function to_iana_tz (val string) as (
    case val
        when 'US/Eastern' then 'America/New_York'
        when 'US/Central' then 'America/Chicago'
        when 'US/Mountain' then 'America/Denver'
        when 'US/Pacific' then 'America/Los_Angeles'
        when 'US/Alaska' then 'America/Anchorage'
        when 'US/Hawaii' then 'Pacific/Honolulu'
        when 'US/Samoa' then 'Pacific/Pago_Pago'
    end
)
;

create temp function likert_to_int (val string) as (
    case
        when val in ('Strongly disagree', 'Never') then 1
        when val in ('Disagree', 'Rather infrequently') then 2
        when val in ('Neither agree nor disagree', 'Some of the time') then 3
        when val in ('Agree', 'Quite often') then 4
        when val in ('Strongly agree', 'Always') then 5
    end
)
;

create or replace table `dkg-phd-thesis.syn_qualtrics.int_intake_responses_scored` as
with
    transformed as (
        select
            response_id,
            survey_id,
            duration,
            to_bool (consent) as has_consented,
            prolific_pid,
            prolific_pid is not null as has_prolific_pid,
            to_bool (age_flag) as is_adult,
            to_bool (fte_flag) as is_fte,
            to_bool (location_flag) as is_domestic,
            to_bool (language_flag) as is_english_proficient,
            cast(phone as int64) as phone_number,
            to_iana_tz (timezone) as time_zone,
            date(selected_date) as followup_date,
            age,
            ethnicity,
            gender_identity as gender,
            job_tenure,
            education_level as edu_lvl,
            to_bool (remote_flag) as is_remote,
            likert_to_int (pa1) as pa1,
            likert_to_int (pa2) as pa2,
            likert_to_int (pa3) as pa3,
            likert_to_int (pa4) as pa4,
            likert_to_int (pa5) as pa5,
            likert_to_int (na1) as na1,
            likert_to_int (na2) as na2,
            likert_to_int (na3) as na3,
            likert_to_int (na4) as na4,
            likert_to_int (na5) as na5,
            likert_to_int (br1) as br1,
            likert_to_int (br2) as br2,
            likert_to_int (br3) as br3,
            likert_to_int (br4) as br4,
            likert_to_int (br5) as br5,
            likert_to_int (vio1) as vio1,
            likert_to_int (vio2) as vio2,
            likert_to_int (vio3) as vio3,
            likert_to_int (vio4) as vio4,
            likert_to_int (js1) as js1
        from
            `dkg-phd-thesis.syn_qualtrics.stg_intake_responses`
    )
select
    *,
    -- means
    ieee_divide(pa1 + pa2 + pa3 + pa4 + pa5, 5) as pa_mean,
    ieee_divide(na1 + na2 + na3 + na4 + na5, 5) as na_mean,
    ieee_divide(br1 + br2 + br3 + br4 + br5, 5) as br_mean,
    ieee_divide(vio1 + vio2 + vio3 + vio4, 4) as vio_mean,
    js1 as js_mean,
    -- sums
    pa1 + pa2 + pa3 + pa4 + pa5 as pa_sum,
    na1 + na2 + na3 + na4 + na5 as na_sum,
    br1 + br2 + br3 + br4 + br5 as br_sum,
    vio1 + vio2 + vio3 + vio4 as vio_sum,
    js1 as js_sum
from
    transformed
;
