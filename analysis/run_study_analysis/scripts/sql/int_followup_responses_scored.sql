-- =============================================================================
-- analysis/run_study_analysis/scripts/sql/int_followup_responses_scored.sql
--
-- Transforms and stores the raw follow-up survey responses from the real study.
-- Source: dkg-phd-thesis.qualtrics.stg_followup_responses
-- LEFT JOIN dkg-phd-thesis.qualtrics.meeting_time_supplement
-- on (response_id, survey_id)
--
-- Scale UDFs:
-- likert_to_int_count    -- count scale (PF, CW, EE, TI): Never...More than three times
-- likert_to_int_agree    -- agreement scale (COMP, AUTO, RELT, ATCB, JS):
-- Strongly disagree...Strongly agree (Somewhat variants)
--
-- Additions vs synthetic:
-- js_tp1_mean   -- Job Satisfaction scored at tp1/9AM only; output as js_tp1_mean.
-- NULL at tp2/tp3 (survey flow placed js1 after survey end; unrecoverable)
-- meetings_time -- Meeting duration in minutes from supplement backfill;
-- COALESCE(stg.meetings_time, supplement.meetings_time), capped at 240.
-- NULL where neither source has a value.
--
-- Deduplication: 14 participants submitted the same survey twice within hours.
-- The source CTE keeps the first submission per (intake_response_id, survey_id)
-- ordered by _created_at asc before scoring.
-- =============================================================================
create temp function likert_to_int_count(val string)
as
    (
        case
            val
            when 'Never'
            then 1
            when 'Once'
            then 2
            when 'Twice'
            then 3
            when 'Three times'
            then 4
            when 'More than three times'
            then 5
        end
    )
;

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

create or replace table `dkg-phd-thesis.qualtrics.int_followup_responses_scored` as
with
    source as (
        -- first submission per (intake_response_id, survey_id) to deduplicate
        select
            f.*,
            s.meetings_time as supplement_meetings_time
        from
            `dkg-phd-thesis.qualtrics.stg_followup_responses` as f
            left join `dkg-phd-thesis.qualtrics.meeting_time_supplement` as s on f.response_id = s.response_id
            and f.survey_id = s.survey_id
        qualify
            row_number() over (
                partition by
                    f.intake_response_id,
                    f.survey_id
                order by
                    f._created_at asc
            ) = 1
    ),
    transformed as (
        select
            response_id,
            survey_id,
            intake_response_id,
            _created_at,
            duration,
            timepoint,
            connect_id,
            regexp_contains(coalesce(connect_id, ''), r'^[A-Za-z0-9]{32}$') as has_connect_id,
            safe_cast(phone_number as int64) as phone_number,
            -- attention check: per-survey expected response
            case
                when (
                    survey_id = 'SV_5nV942MJGubDmqq'
                    and attention_check = 'Once'
                )
                or (
                    survey_id = 'SV_eRKl4lgMZDAurT8'
                    and attention_check = 'Strongly agree'
                )
                or (
                    survey_id = 'SV_6J3svun1r97AAHc'
                    and attention_check = 'Strongly disagree'
                ) then true
                else false
            end as has_passed_attention_check,
            -- meeting load
            least(meetings_num, 8) as meetings_count,
            least(coalesce(meetings_time, supplement_meetings_time), 240) as meetings_time,
            -- PF items (count scale)
            likert_to_int_count (pf1) as pf1,
            likert_to_int_count (pf2) as pf2,
            likert_to_int_count (pf3) as pf3,
            likert_to_int_count (pf4) as pf4,
            likert_to_int_count (pf5) as pf5,
            likert_to_int_count (pf6) as pf6,
            -- CW items (count scale)
            likert_to_int_count (cw1) as cw1,
            likert_to_int_count (cw2) as cw2,
            likert_to_int_count (cw3) as cw3,
            likert_to_int_count (cw4) as cw4,
            likert_to_int_count (cw5) as cw5,
            -- EE items (count scale)
            likert_to_int_count (ee1) as ee1,
            likert_to_int_count (ee2) as ee2,
            likert_to_int_count (ee3) as ee3,
            -- COMP items (agreement scale)
            likert_to_int_agree (comp1) as comp1,
            likert_to_int_agree (comp2) as comp2,
            likert_to_int_agree (comp3) as comp3,
            likert_to_int_agree (comp4) as comp4,
            -- AUTO items (agreement scale)
            likert_to_int_agree (auto1) as auto1,
            likert_to_int_agree (auto2) as auto2,
            likert_to_int_agree (auto3) as auto3,
            likert_to_int_agree (auto4) as auto4,
            -- RELT items (agreement scale)
            likert_to_int_agree (relt1) as relt1,
            likert_to_int_agree (relt2) as relt2,
            likert_to_int_agree (relt3) as relt3,
            likert_to_int_agree (relt4) as relt4,
            -- ATCB items (agreement scale; marker variable)
            likert_to_int_agree (atcb2) as atcb2,
            likert_to_int_agree (atcb5) as atcb5,
            likert_to_int_agree (atcb6) as atcb6,
            likert_to_int_agree (atcb7) as atcb7,
            -- TI (count scale)
            likert_to_int_count (turnover_intention) as turnover_intention,
            -- JS item (agreement scale; tp1/9AM survey only; NULL at tp2/tp3 by survey design)
            likert_to_int_agree (js1) as js1
        from
            source
    )
select
    *,
    -- means
    -- 5-item scales: prorate from available items when >= 4 non-null (>= 80% threshold).
    -- pf3 excluded by design (absent from 1PM/5PM surveys); pf_sum requires all 5 items.
    if(
        (case when pf1 is not null then 1 else 0 end
            + case when pf2 is not null then 1 else 0 end
            + case when pf4 is not null then 1 else 0 end
            + case when pf5 is not null then 1 else 0 end
            + case when pf6 is not null then 1 else 0 end) >= 4,
        ieee_divide(
            coalesce(pf1, 0) + coalesce(pf2, 0) + coalesce(pf4, 0)
            + coalesce(pf5, 0) + coalesce(pf6, 0),
            case when pf1 is not null then 1 else 0 end
            + case when pf2 is not null then 1 else 0 end
            + case when pf4 is not null then 1 else 0 end
            + case when pf5 is not null then 1 else 0 end
            + case when pf6 is not null then 1 else 0 end
        ),
        null
    ) as pf_mean,
    if(
        (case when cw1 is not null then 1 else 0 end
            + case when cw2 is not null then 1 else 0 end
            + case when cw3 is not null then 1 else 0 end
            + case when cw4 is not null then 1 else 0 end
            + case when cw5 is not null then 1 else 0 end) >= 4,
        ieee_divide(
            coalesce(cw1, 0) + coalesce(cw2, 0) + coalesce(cw3, 0)
            + coalesce(cw4, 0) + coalesce(cw5, 0),
            case when cw1 is not null then 1 else 0 end
            + case when cw2 is not null then 1 else 0 end
            + case when cw3 is not null then 1 else 0 end
            + case when cw4 is not null then 1 else 0 end
            + case when cw5 is not null then 1 else 0 end
        ),
        null
    ) as cw_mean,
    ieee_divide(ee1 + ee2 + ee3, 3) as ee_mean,
    ieee_divide(comp1 + comp2 + comp3 + comp4, 4) as comp_mean,
    ieee_divide(auto1 + auto2 + auto3 + auto4, 4) as auto_mean,
    ieee_divide(relt1 + relt2 + relt3 + relt4, 4) as relt_mean,
    ieee_divide(atcb2 + atcb5 + atcb6 + atcb7, 4) as atcb_mean,
    turnover_intention as turnover_intention_mean,
    js1 as js_tp1_mean,
    -- sums
    pf1 + pf2 + pf4 + pf5 + pf6 as pf_sum,
    cw1 + cw2 + cw3 + cw4 + cw5 as cw_sum,
    ee1 + ee2 + ee3 as ee_sum,
    comp1 + comp2 + comp3 + comp4 as comp_sum,
    auto1 + auto2 + auto3 + auto4 as auto_sum,
    relt1 + relt2 + relt3 + relt4 as relt_sum,
    atcb2 + atcb5 + atcb6 + atcb7 as atcb_sum,
    turnover_intention as turnover_intention_sum
from
    transformed
;
