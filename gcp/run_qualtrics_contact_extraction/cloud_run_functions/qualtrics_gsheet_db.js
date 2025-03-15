function onChange(e) {
    if (e.changeType === 'INSERT_ROW') {
        var sheet = e.source.getActiveSheet();
        var payload = {
            sheetName: sheet.getName(),
            changeType: e.changeType,
            timestamp: new Date().toISOString()
        };

        // Replace with your actual Cloud Run URL and a secure way to fetch your API key
        var endpoint = "https://run-qualtrics-contact-extraction-uep2ub7uja-uk.a.run.app";
        var apiKey = "***"; // Consider storing and retrieving this securely

        var options = {
            method: "post",
            contentType: "application/json",
            payload: JSON.stringify(payload),
            headers: {
                "X-API-Key": apiKey
            },
            muteHttpExceptions: true
        };

        var response = UrlFetchApp.fetch(endpoint, options);
        Logger.log("Response from Cloud Run: " + response.getContentText());
    }
}
