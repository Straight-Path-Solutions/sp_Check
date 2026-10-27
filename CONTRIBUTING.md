# Contributing to the sp\_Check Repository

Thanks for stopping by. This page explains how to tell us about a problem or ask for something new, and it should only take a minute to read.

* [Reporting Bugs](#reporting-bugs)
* [Requesting Features](#requesting-features)
* [Pull Requests](#pull-requests)

The short version: we do not accept code contributions here, but we very much want to hear from you when something is broken or missing. Every issue gets read.

## Reporting Bugs

If one of the procedures throws an error, returns a result you know to be wrong, or quietly returns nothing when it should have found something, open an issue:

* [Report a bug or problem](https://github.com/Straight-Path-Solutions/sp_Check/issues)

Before you do, have a quick look through the [open issues](https://github.com/Straight-Path-Solutions/sp_Check/issues) and the [closed issues](https://github.com/Straight-Path-Solutions/sp_Check/issues?q=is:issue+is:closed). Someone may have already run into the same thing, and it may already be fixed in the current version.

The more of the following you can include, the faster we can sort it out:

* Which procedure you were running, and the version you have installed
* The output of `SELECT @@VERSION`, including the edition
* Whether this is a standalone instance, a failover cluster instance, an availability group replica, or Azure SQL Managed Instance
* The exact error text and message number, if you got one
* The parameters you passed in
* The CheckID involved, if the problem is with a specific finding

We would rather have too much detail than not enough. If you cannot share the specifics because of client confidentiality, tell us that and describe what you can. We work in other people's production environments too, and we understand.

## Requesting Features

New check ideas and feature requests are welcome, and they go in the same place as bugs:

* [Request a feature](https://github.com/Straight-Path-Solutions/sp_Check/issues)

Tell us what you are trying to find out about an instance and why it matters in your environment. The reasoning is usually more useful to us than a proposed implementation, because it tells us what the check actually needs to catch.

We read and respond to every feature request. We cannot promise to build all of them, and some will not fit the direction of the suite or will not work reliably across the versions and platforms we support. If we decide not to take something on, we will say so and explain why rather than leaving the issue sitting open indefinitely.

If you are not sure whether an idea is worth raising, raise it. A short issue costs you very little and it may be something we have been meaning to add.

## Pull Requests

**Pull requests are not accepted on this repository.** Only Straight Path Solutions employees commit code here, and forks and pull requests are disabled accordingly.

This is not a comment on the quality of anyone's code. These procedures get run against client production servers, frequently by people who are meeting an instance for the first time, and we keep the review and release process in-house so that we can stand behind everything in them.

Thanks for using our sp\_Check tools!

