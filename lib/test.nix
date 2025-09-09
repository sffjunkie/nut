# Adapted from https://github.com/jetpack-io/nixtest/
# - Passing a 'include' attribute sets the regex used to select files to include
# - Passing a 'exclude' attribute sets the regex used to select files to exclude
# - Passing a 'quiet' attribute set to true to the run function outputs less information
# - Adding a 'skip' attribute to a test skips it
# - Adding a 'skipIf' attribute skips the test if the attribute value is Trueish
# - Requires a reference to `lib` to be passed to the `run` function
{ lib, ... }:
let
  # Function `run` takes a Attribute set as an argument
  # The only required attribute is 'dir' the directory to load tests from.
  # By default it then finds all test files matching the pattern `**/*_test.nix`,
  # and runs all of those tests.
  #
  # Passing an `include` attribute to `run` will only include files that match that pattern.
  # If an `exclude` attribute is also passed then the file name must not match the pattern.
  #
  # Once the tests have run, it prints a summary of the results. If any of
  # the tests failed, it prints the summary by throwing an exception and
  # exiting with a non-zero exit code.
  #
  # Note that every _test.nix file should evaluate to a list of tests. Each test
  # in the list should have the following schema.

  # All attributes are passed through to the test file.

  # Test =  AttrSet {
  #   name     # The name of the test. Used in the test results output
  #   expected # THe expected result of the test
  #   actual   # The actual result of the test
  #   skip     # If set this unconditionally skips the test
  #   skipIf   # If this evaluates to a Trueish value then the test is skipped.
  # }
  #
  # Where Trueish is
  isTrueish =
    value:
    (lib.isList value && value != [ ])
    || (lib.isAttrs value && value != { })
    || (lib.isBool value && value != false)
    || (lib.isString value && value != "")
    || ((lib.isInt value || lib.isFloat value) && value != 0);

  # Run all the tests found in `dir` and show the test results
  run =
    {
      dir,
      include ? ".*_test\.nix",
      exclude ? "",
      quiet ? false,
      ...
    }@inputs:
    let
      updateInputs = inputs // {
        inherit include exclude quiet;
      };
      results = runDir dir updateInputs;
      noMatchText =
        "No test files found matching "
        + "include pattern \"${include}\""
        + " and exclude pattern \"${exclude}\"";
    in
    (if lib.length results != 0 then showTestResults results updateInputs else noMatchText);

  # runDir = path -> list[TestFileResults]
  #
  # TestFileResults = AttrSet {
  #   passed = the results from tests that passed
  #   failed = the results from tests that failed
  #   skipped = list of tests that have been skipped.
  # }
  runDir =
    dir: inputs:
    (
      let
        results = builtins.foldl' (
          acc: filepath:
          (
            let
              tests = import filepath inputs;
              result = runTests tests filepath;
            in
            acc ++ [ result ]
          )
        ) [ ] (testFiles dir inputs);
      in
      results
    );

  # testFiles = path -> list[path]
  #
  # Takes a directory as an argument, finds all test files
  # matching the pattern `*_test.nix` in this directory and its sub-directories.
  testFiles =
    dir: inputs:
    (
      let
        fileTypes = builtins.readDir dir;
        filenames = builtins.attrNames fileTypes;
        allTestFiles = builtins.foldl' (
          acc: filename:
          let
            path = lib.concatStringsSep "/" [
              dir
              "${filename}"
            ];
            fileType = builtins.getAttr filename fileTypes;
            isTestFile =
              (fileType == "regular")
              && (builtins.match inputs.exclude filename) == null
              && (builtins.match inputs.include filename) != null;
          in
          (
            if fileType == "directory" then
              acc ++ (testFiles path)
            else if isTestFile then
              acc ++ [ path ]
            else
              acc ++ [ ]
          )
        ) [ ] filenames;
      in
      allTestFiles
    );

  addFilePath =
    filepath: result:
    (
      let
        newResult = result // {
          path = filepath;
        };
      in
      newResult
    );

  # runTests = list[Test] -> path -> TestFileResults
  #
  # Runs all of the non skipped tests, by calling `evaluateTest` on each of them.
  runTests =
    tests: filepath:
    (
      let
        skipIf = builtins.filter (test: lib.hasAttrByPath [ "skipIf" ] test) tests;
        skipIfSkip = builtins.filter (test: isTrueish test.skipIf) skipIf;
        skipIfRun = builtins.filter (test: !isTrueish test.skipIf) skipIf;
        skippedTests = builtins.filter (test: lib.hasAttrByPath [ "skip" ] test) tests ++ skipIfSkip;
        skipped = map (test: addFilePath filepath test) skippedTests;

        testsToRun =
          builtins.filter (
            test: (!lib.hasAttrByPath [ "skip" ] test) && (!lib.hasAttrByPath [ "skipIf" ] test)
          ) tests
          ++ skipIfRun;

        results = builtins.map (test: addFilePath filepath (evaluateTest test)) testsToRun;

        failed = builtins.filter (test: test.passed == false) results;
        passed = builtins.filter (test: test.passed == true) results;
      in
      {
        inherit failed passed skipped;
      }
    );

  # evaluateTest = Test -> AttrSet
  # Evaluate a single test
  evaluateTest =
    test:
    if test.actual == test.expected then
      {
        name = test.name;
        actual = test.actual;
        expected = test.expected;
        passed = true;
      }
    else
      {
        name = test.name;
        actual = test.actual;
        expected = test.expected;
        passed = false;
      };

  # showTestResults = list[TestFileResults] -> str
  showTestResults =
    results: inputs:
    (
      let
        failed = lib.flatten (map (item: item.failed) results);
        passed = lib.flatten (map (item: item.passed) results);
        skipped = lib.flatten (map (item: item.skipped) results);

        numFailed = builtins.length failed;
        numPassed = builtins.length passed;
        numSkipped = builtins.length skipped;
        numTests = numFailed + numPassed + numSkipped;

        failedText =
          if numFailed > 0 then
            "[FAIL] ${toString numFailed}/${toString numTests} tests failed\n" + (failedMsg failed inputs.quiet)
          else
            "";

        skippedText =
          if numSkipped > 0 then
            "[SKIP] ${toString numSkipped}/${toString numTests} tests skipped\n"
            + (skippedMsg skipped inputs.quiet)
          else
            "";

        passedText = "[PASS] ${toString numPassed}/${toString numTests} tests passed\n";

        msg = failedText + skippedText + passedText;
      in
      msg
    );

  failedMsg =
    failed_tests: quiet:
    (builtins.foldl' (
      acc: result:
      (
        let
          nameText = "    ${result.name}\n";
          verboseText =
            "         File:     ${builtins.toJSON result.path}\n"
            + "         Expected: ${builtins.toJSON result.expected}\n"
            + "         Actual:   ${builtins.toJSON result.actual}\n\n";
        in
        acc + nameText + (if !quiet then verboseText else "")
      )
    ) "" failed_tests);

  skippedMsg =
    skipped_tests: quiet:
    (builtins.foldl' (
      acc: result:
      (
        let
          skipText =
            if result.skip != "" then
              result.skip
            # TODO: skipIf is currently nix code. Need to find way to convert
            # this to a string to display (rnix?)
            else
              "skipIf: ?";
          nameText = "    ${result.name}\n";
          verboseText =
            "         Skipped:  ${skipText}\n" + "         File:     ${builtins.toJSON result.path}\n\n";
        in
        acc + nameText + (if !quiet then verboseText else "")
      )
    ) "" skipped_tests);
in
{
  inherit run;
}
