---
layout: post
title:  "Lesser known Git commands"
date:   2023-07-30 22:06:00 +0800
---
Here are some helpful git commands to use in your software engineering career.

## git commit --fixup

### Scenario: You missed out a code change and you've already made a git commit

This is a simple one. Make your code change, and do the following:

```git
$ git add .
# Use the commit hash that you want to amend
$ git commit --fixup 439692e3fc90825b8b2f3d620af97f64e1379f1d
[main e25cb68] fixup! Add feature 1
 1 file changed, 1 insertion(+), 1 deletion(-)
```

## git bisect

### Scenario: You run `git pull` and the latest `main` branch broke your localhost server

Run `git bisect` to find out why.

```text
GIT-BISECT(1)                            Git Manual                            GIT-BISECT(1)

NAME
       git-bisect - Use binary search to find the commit that introduced a bug
```

From your latest `main` branch, run `git bisect`.

```git
➜  bisect git:(main) git bisect start
status: waiting for both good and bad commits
```

Run `git log` to get the last good commit that you know, perhaps from the commit before you did `git pull`.

```git
➜  bisect git:(main) git bisect good a2096b5275545f6cf855bd57f4ab215ea39118b1
status: waiting for bad commit, 1 good commit known
```

Then get the latest `main` commit hash that's broken for you.

```git
➜  bisect git:(main) git bisect bad d554381e686a5226cbfe0f22edee8bc0a2f98dca
Bisecting: 4 revisions left to test after this (roughly 2 steps)
[3947048ab17458fb723dbb352ece0b60eeb0d73b] Add feature 1

# Git will then checkout to a commit halfway between the latest bad commit and the known good commit.
# Check if this current version works for you. If it does, run the following:
➜  bisect git:(3947048) git bisect good 3947048ab17458fb723dbb352ece0b60eeb0d73b
Bisecting: 2 revisions left to test after this (roughly 1 step)
[8da14f9cfdbfb72ea282bb30f3e783455d7653e7] Change configuration in docker-compose

# Then it checks out to another commit at the midpoint and once again,
# you determine if the current version works. If it does not, run:
➜  bisect git:(8da14f9) git bisect bad 8da14f9cfdbfb72ea282bb30f3e783455d7653e7
Bisecting: 0 revisions left to test after this (roughly 0 steps)
[1a96ff9cdf256072e3afdadfae969a61ab7025b6] Add feature 2

# Finally, we find a good commit after bisecting and we tell git:
➜  bisect git:(1a96ff9) git bisect good 1a96ff9cdf256072e3afdadfae969a61ab7025b6
8da14f9cfdbfb72ea282bb30f3e783455d7653e7 is the first bad commit
commit 8da14f9cfdbfb72ea282bb30f3e783455d7653e7
Author: Tricia Tan <tricia.tzy@tutanota.com>
Date:   Sun Jul 30 19:57:33 2023 +0800

    Change configuration in docker-compose

 test.txt   | 2 +-
 test.txt-e | 6 ++++++
 2 files changed, 7 insertions(+), 1 deletion(-)
 create mode 100644 test.txt-e

```

Et voila! `git bisect` has helped to find the first bad commit `8da14f9`.

To finish up, run `git bisect reset` to go back to where you were.

```git
➜  bisect git:(1a96ff9) git bisect reset
Previous HEAD position was 1a96ff9 Add feature 2
Switched to branch 'main'
```

This is a pretty manual way of finding the first bad commit. Alternatively, you can write a script and automate this process.

```git
$ git bisect start HEAD a2096b5275545f6cf855bd57f4ab215ea39118b1
$ git bisect run ./test.sh
```

## git rebase --update-refs (v2.38)

### Scenario: You are implementing a large feature that changes or introduces multiple files

It's often helpful to break up the work into sub branches that build on top of each other.

[![](https://mermaid.ink/img/pako:eNqVkbEKwzAMRH8laG4oTTbPhX5AVy-KrcQmtR1UeSgh_14XSpeSpNV0oKe7A81gkiVQMHi5ME5Ox6qMSSF4-dYdYzSu6gklMx25Q1NPyFKf3qwjM6YsG8S_zs2uc7Pt_LkM6OOP6GrIas1216Fdy4YDBOLSzpY_zK-NBnEUSIMq0iKPGnRcCodZ0vURDSjhTAfIk0Whs8eBMYDq8Xan5QkE95y-?type=png)](https://mermaid.live/edit#pako:eNqVkbEKwzAMRH8laG4oTTbPhX5AVy-KrcQmtR1UeSgh_14XSpeSpNV0oKe7A81gkiVQMHi5ME5Ox6qMSSF4-dYdYzSu6gklMx25Q1NPyFKf3qwjM6YsG8S_zs2uc7Pt_LkM6OOP6GrIas1216Fdy4YDBOLSzpY_zK-NBnEUSIMq0iKPGnRcCodZ0vURDSjhTAfIk0Whs8eBMYDq8Xan5QkE95y-)

Each part branch is what you will submit for code review, and the final part, `feature/rbac-part-3` is what the final state looks like.

You need to rebase `feature/rbac-part-1` onto latest `main`. Without `--update-refs` you will need to manually check out to each feature branch and run `git rebase --onto`.

Instead, just checkout to your final state branch, `feature/rbac-part-3` and run the following command:

```git
➜  blog git:(feature/rbac-part-3) git rebase -i --root --autosquash --update-refs
Successfully rebased and updated refs/heads/feature/rbac-part-3.
Updated the following refs with --update-refs:
  refs/heads/feature/rbac-part-1
  refs/heads/feature/rbac-part-2
```

Now your git tree should look like this:

[![](https://mermaid.ink/img/pako:eNqVkLEOwjAMRH-l8twK0W6ZkfgA1ixu4jZRSVIZZ0BV_50gsZaAp5N8fnfyBiZZAgWzlyvj6nRsypgUgpff9cgYjWsmQslMJx7RdCuydOeP15FZUpYvjn_JfZXcV_pXLw-zhyphOMqGFgJxQG_L07f3RoM4CqRBFWmRFw067sWHWdLtGQ0o4Uwt5NWi0MXjzBhATXh_0P4CVQ-WWQ?type=png)](https://mermaid.live/edit#pako:eNqVkLEOwjAMRH-l8twK0W6ZkfgA1ixu4jZRSVIZZ0BV_50gsZaAp5N8fnfyBiZZAgWzlyvj6nRsypgUgpff9cgYjWsmQslMJx7RdCuydOeP15FZUpYvjn_JfZXcV_pXLw-zhyphOMqGFgJxQG_L07f3RoM4CqRBFWmRFw067sWHWdLtGQ0o4Uwt5NWi0MXjzBhATXh_0P4CVQ-WWQ)

References:

* [Rost, Tony. “A Beginner’s Guide to GIT BISECT - The Process of Elimination.” Metal Toad, 19 Apr. 2012, https://www.metaltoad.com/blog/beginners-guide-git-bisect-process-elimination.](https://www.metaltoad.com/blog/beginners-guide-git-bisect-process-elimination)

* [Tack, Dylan. “Mechanizing Git Bisect: Bug Hunting for the Lazy.” Metal Toad, 7 Sept. 2010, https://www.metaltoad.com/blog/mechanizing-git-bisect-bug-hunting-lazy.](https://www.metaltoad.com/blog/mechanizing-git-bisect-bug-hunting-lazy)

* [Blau, Taylor. “Highlights from Git 2.38 - The GitHub Blog.” The GitHub Blog, 3 Oct. 2022, https://github.blog/2022-10-03-highlights-from-git-2-38.](https://github.blog/2022-10-03-highlights-from-git-2-38)
