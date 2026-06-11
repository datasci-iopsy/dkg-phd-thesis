-- =============================================================================
-- analysis/run_study_analysis/scripts/sql/fct_panel_responses.sql
--
-- Builds the analytical fact table at participant-timepoint grain (purpose b).
-- Sources: int_intake_responses_scored INNER JOIN int_followup_responses_scored
--
-- Eligibility gates (4): consent, adult, domestic, English proficient.
-- Attention check: listwise deletion -- all timepoints removed for any
-- participant who failed any one attention check.
-- Completeness: only participants with all 3 followup timepoints included.
-- =============================================================================
create or replace table `dkg-phd-thesis.qualtrics.fct_panel_responses` as
with
    intake as (
        select
            *
        from
            `dkg-phd-thesis.qualtrics.int_intake_responses_scored`
        where
            has_consented = true
            and is_adult = true
            and is_domestic = true
            and is_english_proficient = true
    ),
    failed_attention as (
        -- participants who failed any timepoint; used for listwise deletion
        select distinct
            intake_response_id
        from
            `dkg-phd-thesis.qualtrics.int_followup_responses_scored`
        where
            has_passed_attention_check = false
    ),
    followup as (
        -- exclude all timepoints for any participant who failed any attention check
        select
            f.*
        from
            `dkg-phd-thesis.qualtrics.int_followup_responses_scored` as f
        where
            f.intake_response_id not in (select intake_response_id from failed_attention)
    ),
    complete as (
        -- keep only participants who completed all 3 timepoints
        select
            intake_response_id
        from
            followup
        group by
            intake_response_id
        having
            count(distinct timepoint) = 3
    ),
    joined as (
        select
            -- identifiers
            i.response_id,
            -- i.connect_id excluded: direct participant identifier; omitted from version-controlled export
            i.has_connect_id,
            -- i.phone_number excluded: direct participant identifier; omitted from version-controlled export
            f.survey_id as followup_survey_id,
            f.duration,
            f.timepoint,
            -- l2: demographics and recruitment
            i.recruitment_source,
            i.time_zone,
            i.followup_date,
            i.age,
            i.ethnicity,
            i.gender,
            i.job_tenure,
            i.edu_lvl,
            i.is_remote,
            i.work_classification,
            i.work_shift,
            -- l2: affect items (frequency scale)
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
            -- l2: psychological contract items (agreement scale)
            i.br1,
            i.br2,
            i.br3,
            i.br4,
            i.br5,
            i.vio1,
            i.vio2,
            i.vio3,
            i.vio4,
            -- l2: job satisfaction (single item)
            i.js1,
            -- l2: extra intake scales (scored but not in current hypotheses)
            i.jis1,
            i.des1,
            i.des2,
            -- l1: burnout items (count scale)
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
            -- l1: need frustration items (agreement scale)
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
            -- l1: marker variable items (agreement scale)
            f.atcb2,
            f.atcb5,
            f.atcb6,
            f.atcb7,
            -- l1: meeting load
            f.meetings_count,
            f.meetings_time,
            -- l1: turnover intention (count scale)
            f.turnover_intention,
            -- l2: affect means
            i.pa_mean,
            i.na_mean,
            -- l2: psychological contract means
            i.br_mean,
            i.vio_mean,
            -- l2: job satisfaction mean
            i.js_mean,
            -- l2: extra scale means
            i.jis_mean,
            i.des_mean,
            -- l1: burnout means
            f.pf_mean,
            f.cw_mean,
            f.ee_mean,
            -- l1: need frustration means
            f.comp_mean,
            f.auto_mean,
            f.relt_mean,
            -- l1: marker variable mean
            f.atcb_mean,
            -- l1: criterion mean
            f.turnover_intention_mean,
            -- l1: tp1-only JS (NULL at tp2/tp3 by survey design)
            f.js_tp1_mean
        from
            intake as i
            inner join complete as c on i.response_id = c.intake_response_id
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
