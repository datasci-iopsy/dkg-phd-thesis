Qualtrics.SurveyEngine.addOnload(function () {
    var input = this.getQuestionContainer().querySelectorAll("input[type=text]")[0];

    input.setAttribute("type", "date");

    // Format using local date components to avoid UTC offset artifacts.
    // toISOString() converts to UTC, which shifts the date backward for
    // UTC+ timezones (Europe, Asia, Australia), making today selectable.
    function localDateStr(d) {
        return d.getFullYear() + "-"
            + String(d.getMonth() + 1).padStart(2, "0") + "-"
            + String(d.getDate()).padStart(2, "0");
    }

    var today = new Date();
    var tomorrow    = new Date(today.getFullYear(), today.getMonth(), today.getDate() + 1);
    var windowEnd   = new Date(today.getFullYear(), today.getMonth(), today.getDate() + 9);
    var surveyClose = new Date(2026, 5, 12); // June 12 hard cutoff
    var maxDay = windowEnd < surveyClose ? windowEnd : surveyClose;

    input.setAttribute("min", localDateStr(tomorrow));
    input.setAttribute("max", localDateStr(maxDay));

    var errorEl = document.createElement("div");
    errorEl.style.cssText = [
        "display:none",
        "color:#c0392b",
        "font-size:0.875rem",
        "margin-top:0.35rem",
        "padding:0.35rem 0.6rem",
        "background:#fdecea",
        "border-left:3px solid #c0392b",
        "border-radius:2px"
    ].join(";");
    input.parentNode.insertBefore(errorEl, input.nextSibling);

    function showError(msg) {
        errorEl.textContent = msg;
        errorEl.style.display = "block";
        input.setAttribute("aria-invalid", "true");
    }

    function clearError() {
        errorEl.style.display = "none";
        input.removeAttribute("aria-invalid");
    }

    var validating = false;

    input.addEventListener("change", function () {
        if (validating) return;
        validating = true;

        var self = this;

        if (!this.value) {
            clearError();
            validating = false;
            return;
        }

        var selected = new Date(this.value + "T00:00:00");

        if (selected < tomorrow) {
            showError("Please select a future date. Today and past dates are not available.");
            setTimeout(function () { self.value = ""; }, 0);
            validating = false;
            return;
        }

        if (selected > maxDay) {
            showError("Please select a date up to " + maxDay.toLocaleDateString() + ".");
            setTimeout(function () { self.value = ""; }, 0);
            validating = false;
            return;
        }

        clearError();
        validating = false;
    });
});
