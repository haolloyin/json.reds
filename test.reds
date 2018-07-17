Red/System []

#include %reds-json.reds


main-ret:   0
test-count: 0
test-pass:  0
test-index: 0

expect-eq-base: func [
    equality    [logic!]
    expect      [integer!]
    actual      [integer!]
    format      [c-string!]
][
    test-count: test-count + 1
    test-index: test-index + 1
    either equality [
        test-pass: test-pass + 1
        ;printf ["---> PASSED %d, expect: %d, actual: %d" test-index expect actual]
        ;print lf
    ][
        printf ["---> FAILED %d, expect: %d, actual: %d" test-index expect actual]
        print lf
        main-ret: 1
    ]
]

expect-eq-int: func [
    expect  [integer!]
    actual  [integer!]
    /local
        equality    [logic!]
][
    equality: expect = actual
    expect-eq-base equality expect actual "%d"
]

test-parse-null: func [/local v][
    v: declare json-value!
    v/type: JSON_NULL
    expect-eq-int PARSE_OK json/parse v "null"
    expect-eq-int JSON_NULL json/get-type v
]

test-parse-true: func [/local v][
    v: declare json-value!
    v/type: JSON_TRUE
    expect-eq-int PARSE_OK json/parse v "true"
    expect-eq-int JSON_TRUE json/get-type v
]

test-parse-false: func [/local v][
    v: declare json-value!
    v/type: JSON_FALSE
    expect-eq-int PARSE_OK json/parse v "false"
    expect-eq-int JSON_FALSE json/get-type v
]

test-parse-expect-value: func [/local v][
    v: declare json-value!
    v/type: JSON_FALSE
    expect-eq-int PARSE_EXPECT_VALUE json/parse v ""
    expect-eq-int JSON_NULL json/get-type v

    v/type: JSON_FALSE
    expect-eq-int PARSE_EXPECT_VALUE json/parse v " "
    expect-eq-int JSON_NULL json/get-type v
]

test-parse-invalid-value: func [/local v][
    v: declare json-value!
    v/type: JSON_FALSE
    expect-eq-int PARSE_INVALID_VALUE json/parse v "nul"
    expect-eq-int JSON_NULL json/get-type v

    v/type: JSON_FALSE
    expect-eq-int PARSE_INVALID_VALUE json/parse v "?"
    expect-eq-int JSON_NULL json/get-type v
]

test-parse-root-not-singular: func [/local v][
    v: declare json-value!
    v/type: JSON_FALSE
    expect-eq-int PARSE_ROOT_NOT_SINGULAR json/parse v "null x"
    expect-eq-int JSON_NULL json/get-type v
]

test-parse: does [
    test-parse-null
    test-parse-true
    test-parse-false
    test-parse-expect-value
    test-parse-invalid-value
    test-parse-root-not-singular
]

main: func [return: [integer!]][
    test-parse

    printf ["%d/%d (%3.2f%%) passed" test-pass test-count
        100.0 * test-pass / test-count]
    print lf

    main-ret
]

main

