
var epiqueryModule = (function () {

    var epiServer;

    if (document.location.host.startsWith("ship")) {
        epiServer = document.origin + '/epistream-ldap/simple';
    }
    else if (document.location.host.startsWith("localhost")) {
        epiServer = "http://localhost:9090/simple"
    }
    else {
        epiServer = document.origin + '/epistream-ldap/simple';
    }
    console.log("Epiquery server: " + epiServer);

    function formatErrorMessage(templateName, params, err) {
        return err.message + "\nError in epiquery-template " + templateName + "\n with params " + JSON.stringify(params);
    }

    function checkHttpStatus(response) {
        if (response.status >= 200 && response.status < 300) return response;

        return response.json()
        .then(function(x){
            var error = new Error(response.statusText +  ": " + JSON.stringify(x));
            error.response = response;
            throw error;
        });
    }

    function post(driver, templateName, params) {
        var options = {
            method: 'POST',
            headers: {'Accept': 'application/json','Content-Type': 'application/json'},
            body:  JSON.stringify(params)
        };
        if (document.location.host.startsWith("localhost")) {
            options.mode = 'cors';
        }
        else {
            options.credentials = 'include';
        }
        var uri = epiServer + "/" + driver + "/" + templateName;

        var start = new Date().getTime();

        return fetch(uri, options)
            .then(checkHttpStatus)
            .then(function(response) {
                return response.json();
            })
    }

    return {

        run: function(driver, templatePath, data) {
            return post(driver, templatePath, data)
            .then(function(results) {
                if (!results.results) {
                    return;
                }
                if (results.results.length === 1) {
                    if (results.results[0].error)
                        throw new Error(results.results[0].error);
                    if (results.results[0].length ===1 && results.results[0][0].error)
                        throw new Error(results.results[0][0].error); // was seeing this kind of thing when a timeout occurred
                }
                // simple format (workaround epiquery1  bug with empty result sets)
                if (results.results.length === 1) {
                    return results.results[0];
                }
                return results.results;
            })
            .catch(function(err) {
                console.error(formatErrorMessage(templatePath, data, err));
                post('render', templatePath, data)
                .then(function(result) {
                    console.log("Rendered template ===>\n" + result.data);
                })
                .catch(function(err) {
                    console.error("render failed");
                });
            });
        }
    };
})();
