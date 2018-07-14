Red/System []

#include reds-json.reds


main-ret:   0
test-count: 0
test-pass:  0

#define EXPECT_EQ_BASE(equality expect actual format) [
    test-count: test-count + 1
    either equality [test-pass: test-pass + 1][
        printf ["expect: %d actual: %d" expect actual]
        print lf
        main-ret: 1
    ]
]

expect_eq_int: func [
    expect  [integer!]
    actual  [integer!]
    /local
        equality    [logic!]
][
    equality: expect = actual
    EXPECT_EQ_BASE(equality expect actual "%d")
]

test-parse-null: func [
    v [json-value!]
][
    v: declare [json-value!]
    v/type: JSON_TRUE

    EXPECT_EQ_INT(PARSE_OK (json/parse v "null"))
    EXPECT_EQ_INT(JSON_NULL (json/get-type v))
]


test-parse: does [
    test-parse-null
]

main: func [
    test-parse
    printf ["%d/%d (3.2f%%) passed"
        test-pass
        test-count
        test-pass * 100.0 / test-count
    ]
    print lf

    main-ret
]

