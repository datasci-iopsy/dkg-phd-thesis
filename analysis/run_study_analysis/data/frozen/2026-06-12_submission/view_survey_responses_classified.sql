SELECT
    * EXCEPT (work_classification, work_shift),
    COALESCE(work_classification, 'Employee - Full-Time') AS work_classification,
    COALESCE(work_shift, 'first_shift') AS work_shift
FROM `dkg-phd-thesis.qualtrics.stg_intake_responses`

