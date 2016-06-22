Promise  = require 'bluebird'
Promise.longStackTraces()
request  = Promise.promisifyAll require 'request'
_ = require 'lodash'

epiServer = process.env.EPIQUERY_SERVER

class EpiError extends Error
    constructor: (@message) ->
        @name = "EpiError"
        Error.captureStackTrace @, EpiError

getResultsFromResponse = (response, verbose) ->
    if (verbose)
        console.log "response is equal to #{JSON.stringify response}"
        console.log "response status code = #{response.statusCode}"

        if typeof response.body is 'string'
            console.log "response.body is a string"
        else
            console.log "response.body is an object"

        console.log "response.body is equal to #{response.body}"

    results = if typeof response.body is 'string' then JSON.parse response.body else response.body

    # with single or multiple result sets, simple format
    # results (as above) is:
    #
    # {} JSON
    #    [] results
    #       [] 0
    #           {} 0
    #           {} 1
    #       [] 1
    #           {} 0
    #           {} 1
    # 
    # sql with some kind of error:
    #   
    # {} JSON
    #    [] results
    #       {} 0
    #           message: "error"
    #           error:  "Incorrect syntax near 'Bleh!'."
    #           {} errorDetail
    #               message:
    #               code:
    #               number:
    #               state:
    #               class:
    #               serverName:
    #               procName:
    #               lineNumber
    #
    if response.statusCode isnt 200
        throw new Error "HTTP status #{response.statusCode}: ", response.body

    resultSets = results.results;

    if resultSets.length > 0 and resultSets[0].error
        if resultSets[0].errorDetail
            throw new Error JSON.stringify resultSets[0].errorDetail
        else
            throw new Error resultSets[0].error    

    if (verbose)
        console.log "Result sets: #{resultSets.length}"

        _.forEach results.results, (v,i) ->
            console.log "Result set #{i+1} has #{v.length} records"

    resultSets

class EpiRequest
    constructor: ({verbose} = {}) ->
        @verbose = verbose

    run: (templateName, params) ->
        options =
            uri: "#{epiServer}/#{templateName}.mustache"
            json: params

        console.log "Epiquery run: #{templateName}" #if @verbose

        return request.postAsync options
        .then (response) =>
            resultSets = getResultsFromResponse response, @verbose
            if (resultSets.length == 1)
                console.log "Returning result set: #{JSON.stringify resultSets[0]}" if @verbose
                return resultSets[0]
            console.log "Returning result sets: #{JSON.stringify resultSets}" if @verbose  
            return resultSets

        .catch (error) =>
            # we might get here if epiquery server cannot be found
            # or there was an sql error
            # or an error in epiquery
            msg = "epiquery-template = #{templateName}.mustache\nparams = #{JSON.stringify params}"
            throw new EpiError "#{msg}\n#{error.message}"

module.exports = EpiRequest


