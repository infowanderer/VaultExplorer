# Exact duplicate review (F07, first slice)

Photo sorter → More → Find exact duplicates scans the selected photographs, or
the current filtered grid if nothing is batch-selected. The limit is 500 distinct
file handles; a larger selection is refused instead of silently truncated.

The native serial worker first groups files by size. It hashes only size groups
with peers, using the existing bounded streaming SHA-256 reader. Matching groups
require size and full hash equality, stable identity/size/mtime during the read,
and a final metadata recheck of group members. A detected change or cancellation
aborts the report; no partial success is published. Cancellation also applies
when the dialog closes or the app leaves the foreground. UI progress is advisory.

Reports contain paths, file sizes and matching groups in memory only. They never
create transfer jobs, change reviews, move files, delete media or write a cache.
Results describe bytes when checked; later external edits can invalidate them.
Hard links can appear in a group, so group sizes are not claimed as reclaimable
space. Empty files can match. This is exact-content matching, not perceptual
similarity or AI. Side-by-side Dupe Duel, perceptual hashing and video-gallery
entry points remain future work.

Five native synthetic-filesystem cases cover exact matches, same-size different
content, singleton read avoidance, empty files, cancellation, source changes and
batch bounds. Six widget cases cover narrow reports, no matches, invalid report
members, cancelled late results, lifecycle cancellation and oversized input. All
pass. The integrated Flutter suite passes 3,911 tests. The full native release build, signed APK checks and 77 targeted
Android unit tests pass; see [the receipt](BUILD-62-PROGRESS.md). Real document
providers still require device validation.
