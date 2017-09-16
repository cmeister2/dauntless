# Parameters for creating the test file
TEST_DATA_FILE := ./testdns.json.gz
TEST_DATA_LINES := 500000

# The data file which is used as input to this whole process
DATA_FILE ?= $(TEST_DATA_FILE)
DATA_FILE_DIR := $(dir $(DATA_FILE))
DATA_FILE_BASE := $(notdir $(DATA_FILE))

# Name field from the data set
NAME_DATA_FILE := $(DATA_FILE_DIR)name_$(DATA_FILE_BASE)

# Subdomain from name set
SUB_DATA_FILE := $(DATA_FILE_DIR)subdomain_$(DATA_FILE_BASE)
SUBSET_SUB_DATA_FILE := $(DATA_FILE_DIR)subset_subdomain_$(DATA_FILE_BASE)
SORTED_SUB_DATA_FILE := $(DATA_FILE_DIR)sorted_sub_$(DATA_FILE_BASE)
COUNTED_SUB_DATA_FILE := $(DATA_FILE_DIR)counted_sub_$(DATA_FILE_BASE)
TOP_SUB_DATA_FILE := $(DATA_FILE_DIR)top_sub_$(DATA_FILE_BASE)

NUM_PROCS := $(shell nproc)
ifeq ($(NUM_PROCS),)
NUM_PROCS := 1
endif

# Options for Sort
SORT_MEMORY_LIMIT ?= 2G
SORT_MEMORY_FOLDER ?= $(DATA_FILE_DIR)/.sorttmp

# Print a summary of the information
$(info ** [Step 0] Data File               $(DATA_FILE))
$(info ** [Step 1] Name Data               $(NAME_DATA_FILE))
$(info ** [Step 2] Subdomain Data          $(SUB_DATA_FILE))
$(info ** [Step 3] Sorted Subdomain Data   $(SORTED_SUB_DATA_FILE))
$(info ** [Step 4] Counted Subdomain Data  $(COUNTED_SUB_DATA_FILE))
$(info ** [Step 5] Top Subdomain Data      $(TOP_SUB_DATA_FILE))
# $(info ** [Step 5] Filtered Pinyin Data $(NONPINYIN_DATA_FILE))
$(info ** NUM PROCS $(NUM_PROCS))
$(info ** SORT OPTIONS $(SORT_MEMORY_LIMIT) $(SORT_MEMORY_FOLDER))

# Make an "all" target.
all: step5

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
	@echo "Step 1 (jq extraction): Creating $@ from $<"
	pv -cN input $< | \
		pigz -dc | \
		parallel --no-notice --pipe --line-buffer --block 50M jq -r .name | \
		pv -cN postparallel | \
		uniq | \
		pv -cN postuniq | \
		pigz -c | \
		pv -cN output > $@

# Use tldextract in python to extract the subdomain.
# This filters out all domains which don't have a subdomain.
step2: $(SUB_DATA_FILE)
$(SUB_DATA_FILE): $(NAME_DATA_FILE)
	@echo "Step 2 (subdomain extraction): Creating $@ from $<"
	pv -cN input $< | \
		pigz -dc | \
		parallel --no-notice --pipe --line-buffer --block 50M python3 ./subdomain.py | \
		pv -cN postpython | \
		pigz -c | \
		pv -cN output > $@

# At this point we're going to sort the subdomains ready for counting.
step3: $(SORTED_SUB_DATA_FILE)
$(SORTED_SUB_DATA_FILE): $(SUB_DATA_FILE)
	@echo "Step 3 (subdomain sorting): Creating $@ from $<"
	pv -cN input $< | \
		pigz -dc | \
		sort --parallel=$(NUM_PROCS) -S $(SORT_MEMORY_LIMIT) -T $(SORT_MEMORY_FOLDER) | \
		pigz -c | \
		pv -cN output > $@

# Count the instances of the subdomains.
step4: $(COUNTED_SUB_DATA_FILE)
$(COUNTED_SUB_DATA_FILE): $(SORTED_SUB_DATA_FILE)
	@echo "Step 4 (subdomain counting): Creating $@ from $<"
	pv -cN input $< | \
		pigz -dc | \
		uniq -c | \
		pigz -c | \
		pv -cN output > $@

# Reverse sort the subdomains by the numeric count to get the top domains
# including pinyin.
step5: $(TOP_SUB_DATA_FILE)
$(TOP_SUB_DATA_FILE): $(COUNTED_SUB_DATA_FILE)
	@echo "Step 5 (top subdomains): Creating $@ from $<"
	pv -cN input $< | \
		pigz -dc | \
		sort -rg --parallel=$(NUM_PROCS) -S $(SORT_MEMORY_LIMIT) -T $(SORT_MEMORY_FOLDER) | \
		pigz -c | \
		pv -cN output > $@

# Use the filterpinyin script to filter out domains which look like pinyin.
# This doesn't have to be perfect but we want to get rid of the most obvious ones.
nonstep5: $(NONPINYIN_DATA_FILE)
$(NONPINYIN_DATA_FILE): $(COUNTED_SUB_DATA_FILE)
	@echo "Step 5 (pinyin filtering): Creating $@ from $< [SLOW]"
	pv -cN input $< | \
		pigz -dc | \
		parallel --no-notice --pipe --line-buffer --block 50M python3 ./filterpinyin.py | \
		pigz -c | \
		pv -cN output > $@

# Have a target to clean up all generated files
.PHONY: clean
clean:
	@rm -fv $(NAME_DATA_FILE) \
		$(SUB_DATA_FILE) \
		$(SORTED_SUB_DATA_FILE) \
		$(COUNTED_SUB_DATA_FILE)
