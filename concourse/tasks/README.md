### Concourse Tasks

These are intended ot be generic tasks to replace the OS specific ones in the
`concourse` directory above.  They are currently being used in the release
pipeline for GPDB.  The testing pipeline will need to  be updated to use these
as well.

#### Changes from above tasks

  - All tasks require the pipeline to set the `image` for the task.  This let's
    use re-use for multiple platforms
  - Scripts being called no longer take arguments, instead the task uses the
    `param` feature to set the required OS variables.  These again can be
    overridden/specified by the pipeline which uses these tasks

**Note:** The scripts used by these tasks are copies of the original scripts
with slight modifications to the expected location of the GPDB install as well
as switching to OS invironment variables from script arguments.
