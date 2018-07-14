Red/System []

#enum json-type! [
    JSON_NULL: 1
    JSON_FALSE
    JSON_TRUE
    JSON_NUMBER
    JSON_STRING
    JSON_ARRAY
    JSON_OBJECT
]

#enum parse-result-type! [
    PARSE_OK
    PARSE_EXPECT_VALUE
    PARSE_INVALID_VALUE
    PARSE_ROOT_NOT_SINGULAR
]

json-value!: alias struct! [
    type [json-type!]
]

json: context [
    parse: func [
        v       [json-value!]
        json    [c-string!]
        return: [parse-result-type!]
    ][
        
    ]

    get-type: func [
        v       [json-value!]
        return: [json-type!]
    ][
        
    ]
]



