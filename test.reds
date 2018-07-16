Red/System []

#include %reds-json.reds


main-ret:   0
test-count: 0
test-pass:  0

expect-eq-base: func [
    equality    [logic!]
    expect      [integer!]
    actual      [integer!]
    format      [c-string!]
][
    test-count: test-count + 1
    either equality [test-pass: test-pass + 1][
        printf ["FAILED >> expect: %d, actual: %d" expect actual]
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

test-parse-null: func [
    /local v
][
    v: declare json-value!
    v/type: JSON_TRUE

    expect-eq-int PARSE_OK json/parse v "null"
    expect-eq-int JSON_NULL json/get-type v
    expect-eq-int PARSE_OK json/parse v "false"
    expect-eq-int PARSE_OK json/parse v "true"
]


test-parse: does [
    test-parse-null
]

main: func [
    return: [integer!]
][
    test-parse

    printf ["%d/%d (%3.2f%%) passed" test-pass test-count
        100.0 * test-pass / test-count]
    print lf

    main-ret
]

main

