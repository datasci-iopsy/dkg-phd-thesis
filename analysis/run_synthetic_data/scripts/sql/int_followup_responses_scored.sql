-- =============================================================================
-- analysis/run_synthetic_data/scripts/sql/int_followup_responses_scored.sql
--
-- Transforms and stores the raw follow-up survey responses.
-- =============================================================================
create temp function likert_to_int (val string) as (
    case
        when val in ('Strongly disagree', 'Never') then 1
        when val in ('Disagree', 'Once') then 2
        when val in ('Neither agree nor disagree', 'Twice') then 3
        when val in ('Agree', 'Three times') then 4
        when val in ('Strongly agree', 'More than three times') then 5
    end
)
;

create or replace table `dkg-phd-thesis.syn_qualtrics.int_followup_responses_scored` as
with
    transformed as (
        select
            response_id,
            survey_id,
            duration,
            timepoint,
            connect_id,
            connect_id is not null as has_connect_id,
            safe_cast(phone_number as int64) as phone_number,
            likert_to_int (pf1) as pf1,
            likert_to_int (pf2) as pf2,
            likert_to_int (pf3) as pf3,
            likert_to_int (pf4) as pf4,
            likert_to_int (pf5) as pf5,
            likert_to_int (pf6) as pf6,
            likert_to_int (cw1) as cw1,
            likert_to_int (cw2) as cw2,
            likert_to_int (cw3) as cw3,
            likert_to_int (cw4) as cw4,
            likert_to_int (cw5) as cw5,
            likert_to_int (ee1) as ee1,
            likert_to_int (ee2) as ee2,
            likert_to_int (ee3) as ee3,
            likert_to_int (comp1) as comp1,
            likert_to_int (comp2) as comp2,
            likert_to_int (comp3) as comp3,
            likert_to_int (comp4) as comp4,
            likert_to_int (auto1) as auto1,
            likert_to_int (auto2) as auto2,
            likert_to_int (auto3) as auto3,
            likert_to_int (auto4) as auto4,
            likert_to_int (relt1) as relt1,
            likert_to_int (relt2) as relt2,
            likert_to_int (relt3) as relt3,
            likert_to_int (relt4) as relt4,
            likert_to_int (atcb2) as atcb2,
            likert_to_int (atcb5) as atcb5,
            likert_to_int (atcb6) as atcb6,
            likert_to_int (atcb7) as atcb7,
            case
                when (
                    survey_id = "SV_5nV942MJGubDmqq"
                    and attention_check = "Once" -- ! UPDATE WITH OFFICIAL VALUES
                )
                or (
                    survey_id = "SV_eRKl4lgMZDAurT8" -- ! UPDATE WITH OFFICIAL VALUES
                    and attention_check = "Once"
                )
                or (
                    survey_id = "SV_6J3svun1r97AAHc" -- ! UPDATE WITH OFFICIAL VALUES
                    and attention_check = "Once"
                ) then true
                else false
            end as has_passed_attention_check,
            -- todo: determine validity of meeting cap at 8 (4-hour block/30-minute median meeting assumption)
            least(cast(meetings_num as int64), 8) as meetings_count,
            least(cast(meetings_time as int64), 240) as meetings_mins, -- * capped at upper bound of 4 hr block
            likert_to_int (turnover_intention) as turnover_intention,
        from
            `dkg-phd-thesis.syn_qualtrics.stg_followup_responses`
    )
select
    *,
    -- means
    ieee_divide(pf1 + pf2 + pf3 + pf4 + pf5 + pf6, 6) as pf_mean,
    ieee_divide(cw1 + cw2 + cw3 + cw4 + cw5, 5) as cw_mean,
    ieee_divide(ee1 + ee2 + ee3, 3) as ee_mean,
    ieee_divide(comp1 + comp2 + comp3 + comp4, 4) as comp_mean,
    ieee_divide(auto1 + auto2 + auto3 + auto4, 4) as auto_mean,
    ieee_divide(relt1 + relt2 + relt3 + relt4, 4) as relt_mean,
    ieee_divide(atcb2 + atcb5 + atcb6 + atcb7, 4) as atcb_mean,
    turnover_intention as turnover_intention_mean,
    -- sums
    pf1 + pf2 + pf3 + pf4 + pf5 + pf6 as pf_sum,
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
