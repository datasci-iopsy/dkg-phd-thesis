-- =============================================================================
-- analysis/run_synthetic_data/scripts/sql/fct_syn_all_responses.sql
--
-- Transforms, joins, and stores both intake and follow-up survey responses.
-- =============================================================================
-- create or replace table `dkg-phd-thesis.qualtrics.fct_syn_all_responses` as
with
    intake as (
        select
            *
        from
            `dkg-phd-thesis.qualtrics.int_syn__intake_responses_scored`
        where
            has_consented = true
            and is_adult = true
            and is_fte = true
            and is_domestic = true
            and is_english_proficient = true
    ),
    followup as (
        select
            *
        from
            `dkg-phd-thesis.qualtrics.int_syn__followup_responses_scored`
        where
            has_passed_attention_check = true
    ),
    joined as (
        select
            -- identifiers
            i.response_id,
            i.prolific_pid,
            i.has_prolific_pid,
            i.phone_number,
            f.survey_id as followup_survey_id,
            f.timepoint,
            -- l2: demographics & screening
            i.time_zone,
            i.followup_date,
            i.age,
            i.ethnicity,
            i.gender,
            i.job_tenure,
            i.edu_lvl,
            i.is_remote,
            -- l2: affect (scored)
            i.pa_mean,
            i.na_mean,
            -- l2: psychological contract (scored)
            i.br_mean,
            i.vio_mean,
            -- l2: job satisfaction (scored)
            i.js_mean,
            -- l1: burnout (scored)
            f.pf_mean,
            f.cw_mean,
            f.ee_mean,
            -- l1: need frustration (scored)
            f.comp_mean,
            f.auto_mean,
            f.relt_mean,
            -- l1: marker variable (scored)
            f.atcb_mean,
            -- l1: meetings
            f.meetings_count,
            f.meetings_mins,
            -- l1: criterion (scored)
            f.turnover_intention_mean,
        from
            intake as i
            inner join followup as f on i.response_id = f.response_id
    )
select
    *
from
    joined
order by
    followup_date desc,
    response_id,
    timepoint asc
;
