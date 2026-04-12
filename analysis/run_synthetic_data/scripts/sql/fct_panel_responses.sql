-- =============================================================================
-- analysis/run_synthetic_data/scripts/sql/fct_syn_all_responses.sql
--
-- Transforms, joins, and stores both intake and follow-up survey responses.
-- =============================================================================
create or replace table `dkg-phd-thesis.syn_qualtrics.fct_panel_responses` as
with
    intake as (
        select
            *
        from
            `dkg-phd-thesis.syn_qualtrics.int_intake_responses_scored`
        where
            has_consented = true
            and is_adult = true
            and is_fte = true
            and is_domestic = true
            and is_english_proficient = true
    ),
    failed_attention as (
        -- participants who failed any timepoint; used for listwise deletion
        select distinct
            intake_response_id
        from
            `dkg-phd-thesis.syn_qualtrics.int_followup_responses_scored`
        where
            has_passed_attention_check = false
    ),
    followup as (
        -- exclude all timepoints for any participant who failed any attention check
        select
            f.*
        from
            `dkg-phd-thesis.syn_qualtrics.int_followup_responses_scored` as f
        where
            f.intake_response_id not in (
                select
                    intake_response_id
                from
                    failed_attention
            )
    ),
    joined as (
        select
            -- identifiers
            i.response_id,
            i.connect_id,
            i.has_connect_id,
            i.phone_number,
            f.survey_id as followup_survey_id,
            f.duration,
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
            -- l1: affect items
            i.pa1,
            i.pa2,
            i.pa3,
            i.pa4,
            i.pa5,
            i.na1,
            i.na2,
            i.na3,
            i.na4,
            i.na5,
            i.br1,
            i.br2,
            i.br3,
            i.br4,
            i.br5,
            i.vio1,
            i.vio2,
            i.vio3,
            i.vio4,
            i.js1,
            f.pf1,
            f.pf2,
            f.pf3,
            f.pf4,
            f.pf5,
            f.pf6,
            f.cw1,
            f.cw2,
            f.cw3,
            f.cw4,
            f.cw5,
            f.ee1,
            f.ee2,
            f.ee3,
            f.comp1,
            f.comp2,
            f.comp3,
            f.comp4,
            f.auto1,
            f.auto2,
            f.auto3,
            f.auto4,
            f.relt1,
            f.relt2,
            f.relt3,
            f.relt4,
            f.atcb2,
            f.atcb5,
            f.atcb6,
            f.atcb7,
            f.meetings_count,
            f.meetings_mins,
            f.turnover_intention,
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
            -- l1: criterion (scored)
            f.turnover_intention_mean,
        from
            intake as i
            inner join followup as f on i.response_id = f.intake_response_id
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
