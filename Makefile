# Parameters for creating the test file
TEST_DATA_FILE := ./testdns.json.gz
TEST_DATA_LINES := 500000

# The data file which is used as input to this whole process
DATA_FILE ?= $(TEST_DATA_FILE)
DATA_FILE_DIR := $(dir $(DATA_FILE))
DATA_FILE_BASE := $(notdir $(DATA_FILE))

# Name field from the data set
NAME_DATA_FILE := $(DATA_FILE_DIR)name_$(DATA_FILE_BASE)

# Subdomain and TLD from name set
SUBTLD_DATA_FILE := $(DATA_FILE_DIR)subtld_$(DATA_FILE_BASE)

# Get the number of processors available for multithreaded apps
NUM_PROCS := $(shell nproc)
ifeq ($(NUM_PROCS),)
NUM_PROCS := 1
endif

# Options for Sort
SORT_MEMORY_LIMIT ?= 2G
SORT_MEMORY_FOLDER ?= $(DATA_FILE_DIR)/.sorttmp

# Print a summary of the information
$(info ** DATA FILE $(DATA_FILE))
$(info ** NAME DATA $(NAME_DATA_FILE))
$(info ** SUBTLD DATA $(SUBTLD_DATA_FILE))
$(info ** NUM PROCS $(NUM_PROCS))
$(info ** SORT OPTIONS $(SORT_MEMORY_LIMIT) $(SORT_MEMORY_FOLDER))

# Make an "all" target.
all: step2

# For the purposes of CI, have a test data set of the first TEST_DATA_LINES
# lines of the data set.
create_test_data: $(TEST_DATA_FILE)
$(TEST_DATA_FILE):
	@if [ $(TEST_DATA_FILE) = $(DATA_FILE) ]; \
		then \
			echo "Test data cannot be created from itself"; \
			exit 1; \
		fi
	@echo "Creating $@"
	pv $(DATA_FILE) | pigz -dc | head -$(TEST_DATA_LINES) | pigz -c > $@

# Use jq with parallels to generate the data set. Use line-buffer as a speed-up
# which preserves lines (at the expense of CPU).  Use a big buffer because
# otherwise jq doesn't do enough work. Finally, pipe everything to uniq
# to naively deduplicate the output.
step1: $(NAME_DATA_FILE)
$(NAME_DATA_FILE): $(DATA_FILE)
	@echo "Step 1: Creating $@ from $<"
	pv -cN input $< | \
		pigz -dc | \
		parallel --no-notice --pipe --line-buffer --block 50M jq -r .name | \
		pv -cN postparallel | \
		uniq | \
		pv -cN postuniq | \
		pigz -c | \
		pv -cN output > $@

# Use tldextract in python to extract the subdomain and tld. Output them as
# a colon-separated file. This filters out all domains which don't have a 
# subdomain.
step2: $(SUBTLD_DATA_FILE)
$(SUBTLD_DATA_FILE): $(NAME_DATA_FILE)
	@echo "Step 2: Creating $@ from $<"
	pv -cN input $< | \
		pigz -dc | \
		parallel --no-notice --pipe --line-buffer --block 50M python3 ./subtld.py | \
		pv -cN postpython | \
		pigz -c | \
		pv -cN output > $@

# Have a target to clean up all generated files
.PHONY: clean
clean:
	@rm -fv $(NAME_DATA_FILE) \
		$(SUBTLD_DATA_FILE)
