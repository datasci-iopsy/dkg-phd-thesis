-- =============================================================================
-- analysis/run_study_analysis/scripts/sql/fct_participation_summary.sql
--
-- Builds a participant-grain completion funnel table (reporting, purpose a).
-- Source: int_intake_responses_scored LEFT JOIN int_followup_responses_scored
--
-- Output columns (1 row per intake respondent):
-- eligibility flags, per-timepoint completion and attention status,
-- n_followups (0-3), n_total (1-4), completion_rate, timestamps.
-- =============================================================================
create or replace table `dkg-phd-thesis.qualtrics.fct_participation_summary` as
with
    followup_agg as (
        select
            intake_response_id,
            countif(timepoint = 1) > 0 as has_completed_tp1,
            countif(timepoint = 2) > 0 as has_completed_tp2,
            countif(timepoint = 3) > 0 as has_completed_tp3,
            max(
                case
                    when timepoint = 1 then has_passed_attention_check
                end
            ) as has_passed_attn_tp1,
            max(
                case
                    when timepoint = 2 then has_passed_attention_check
                end
            ) as has_passed_attn_tp2,
            max(
                case
                    when timepoint = 3 then has_passed_attention_check
                end
            ) as has_passed_attn_tp3,
            count(*) as n_followups,
            min(_created_at) as first_followup_at,
            max(_created_at) as last_followup_at
        from
            `dkg-phd-thesis.qualtrics.int_followup_responses_scored`
        group by
            intake_response_id
    )
select
    i.response_id,
    -- i.connect_id excluded: direct participant identifier; omitted from version-controlled export
    i.has_connect_id,
    i.recruitment_source,
    i.followup_date,
    i._created_at as intake_created_at,
    -- eligibility flags (4 gates; fte_flag deprecated and removed)
    i.has_consented,
    i.is_adult,
    i.is_domestic,
    i.is_english_proficient,
    (
        i.has_consented
        and i.is_adult
        and i.is_domestic
        and i.is_english_proficient
    ) as is_eligible,
    -- completion funnel
    coalesce(f.has_completed_tp1, false) as has_completed_tp1,
    coalesce(f.has_completed_tp2, false) as has_completed_tp2,
    coalesce(f.has_completed_tp3, false) as has_completed_tp3,
    f.has_passed_attn_tp1,
    f.has_passed_attn_tp2,
    f.has_passed_attn_tp3,
    coalesce(f.n_followups, 0) as n_followups,
    1 + coalesce(f.n_followups, 0) as n_total,
    ieee_divide(coalesce(f.n_followups, 0), 3) as completion_rate,
    f.first_followup_at,
    f.last_followup_at
from
    `dkg-phd-thesis.qualtrics.int_intake_responses_scored` as i
    left join followup_agg as f on i.response_id = f.intake_response_id
order by
    i.followup_date desc,
    i.response_id
;
