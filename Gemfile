source "https://rubygems.org"

gemspec

gem "rake"

# 0.22 runs its report from its own at_exit hook, which a heckle run
# reaches; 1.x defers it to Minitest.after_run, which heckle never fires.
gem "simplecov", "~> 0.22.0"
