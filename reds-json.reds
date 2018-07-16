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

#enum json-parse-result! [
    PARSE_OK: 10
    PARSE_EXPECT_VALUE
    PARSE_INVALID_VALUE
    PARSE_ROOT_NOT_SINGULAR
]

json-value!: alias struct! [
    type [json-type!]
]

json-conetxt!: alias struct! [
    json [byte-ptr!]
]

json: context [

    parse: func [
        v       [json-value!]
        json    [c-string!]
        return: [json-parse-result!]
        /local  ctx
    ][
        ctx: declare json-conetxt!
        assert ctx <> null

        ctx/json: as byte-ptr! json
        v/type: JSON_NULL

        parse-whitespace ctx
        parse-value ctx v
    ]

    get-type: func [
        v       [json-value!]
        return: [json-type!]
    ][
        v/type
    ]

    parse-whitespace: func [
        ctx     [json-conetxt!]
        /local  c str
    ][
        c: ctx/json
        while [any [c/value = space c/value = tab c/value = cr c/value = lf]][
            print-line "skip a whitespace"
            c: c + 1
        ]
        ctx/json: c
    ]

    expect: func [
        ctx     [json-conetxt!]
        char    [byte!]
        /local  c
    ][
        c: ctx/json
        assert c/value = char
        ctx/json: ctx/json + 1
    ]

    parse-null: func [
        ctx     [json-conetxt!]
        v       [json-value!]
        return: [json-parse-result!]
        /local  c str
    ][
        expect ctx #"n"

        str: as-c-string ctx/json
        if any [
            str/1 <> #"u"
            str/2 <> #"l"
            str/3 <> #"l"
        ][return PARSE_INVALID_VALUE]

        ctx/json: ctx/json + 3
        v/type: JSON_NULL
        PARSE_OK
    ]

    parse-value: func [
        ctx     [json-conetxt!]
        v       [json-value!]
        return: [json-parse-result!]
        /local  c
    ][
        c: ctx/json
        if null? c [return PARSE_EXPECT_VALUE]

        switch c/value [
            #"n"    [return parse-null ctx v]
            default [return PARSE_INVALID_VALUE]
        ]
    ]
]



