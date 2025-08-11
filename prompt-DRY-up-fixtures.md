# Porting Ably LiveObjects JavaScript integration tests to Swift

## Overview

Take a look at the attached Repomix output. This belongs to a codebase called ably-js, which offers the same LiveObjects functionality as this Swift plugin. The file objects.test.js offers various integration tests for the LiveObjects functionality. I wish to port these tests to Swift.

I have already:

- ported the ObjectsHelper class
- chosen how to map the JavaScript tests' parameterised testing to Swift Testing
- ported the objectSyncScenarios, applyOperationsScenarios, writeAPIScenarios, subscriptionCallbacksScenarios, and applyOperationsDuringSyncScenarios (with the aid of an LLM)

You can see all of this in @ObjectsIntegrationTests.swift.

The LLM that ported the tests did not do a good job of porting the fixtures. Instead of porting the top level fixtures, it has created individual local variable fixtures in each of the tests. I wish for you to rectify this mistake and DRY up these fixtures. I want you to create top level variables for primitiveKeyData, primitiveMapsFixtures, and countersFixtures, and update the tests to use these.

In the case where the local variable in a test currently has some additional fields, such as the swiftValue or the restData, I want you to include this value in the top level fixtures, such that the top level data is the union of all the fields in the current local variables. And I want there to be a comment explaining exactly why this additional field exists.
