# Parameters for creating the test file
TEST_DATA_FILE := ./testdns.json.gz
TEST_DATA_LINES := 500000

# The data file which is used as input to this whole process
DATA_FILE ?= $(TEST_DATA_FILE)
DATA_FILE_DIR := $(dir $(DATA_FILE))
DATA_FILE_BASE := $(notdir $(DATA_FILE))

# Name field from the data set
NAME_DATA_FILE := $(DATA_FILE_DIR)step1.name_$(DATA_FILE_BASE)

# Subdomain from name set
SUB_DATA_FILE := $(DATA_FILE_DIR)step2.subdomain_$(DATA_FILE_BASE)
SORTED_SUB_DATA_FILE := $(DATA_FILE_DIR)step3.sorted_sub_$(DATA_FILE_BASE)
COUNTED_SUB_DATA_FILE := $(DATA_FILE_DIR)step4.counted_sub_$(DATA_FILE_BASE)
TOP_SUB_DATA_FILE := $(DATA_FILE_DIR)step5.top_sub_$(DATA_FILE_BASE)
TOP_X_SUBS_DATA_FILE := $(DATA_FILE_DIR)step6.top_xsubs_$(DATA_FILE_BASE)
TOP_X_SUBS_NP_DATA_FILE := $(DATA_FILE_DIR)step7.top_xsubs_np_$(DATA_FILE_BASE)

TOP_X_SUBS_P_DATA_FILE := $(DATA_FILE_DIR)step7.top_xsubs_p_$(DATA_FILE_BASE).log
SUBSET_SUB_DATA_FILE := $(DATA_FILE_DIR)subset_subdomain_$(DATA_FILE_BASE)

NUM_PROCS := $(shell nproc)
ifeq ($(NUM_PROCS),)
NUM_PROCS := 1
endif

# Options for Sort
SORT_MEMORY_LIMIT ?= 2G
SORT_MEMORY_FOLDER ?= $(DATA_FILE_DIR)/.sorttmp

# Options for limiting output
TOP_FIRST_LIMIT ?= 2000000

# Print a summary of the information
$(info ** [Step 0] Data File               $(DATA_FILE))
$(info ** [Step 1] Name Data               $(NAME_DATA_FILE))
$(info ** [Step 2] Subdomain Data          $(SUB_DATA_FILE))
$(info ** [Step 3] Sorted Subdomain Data   $(SORTED_SUB_DATA_FILE))
$(info ** [Step 4] Counted Subdomain Data  $(COUNTED_SUB_DATA_FILE))
$(info ** [Step 5] Top Subdomain Data      $(TOP_SUB_DATA_FILE))
$(info ** [Step 6] Top $(TOP_FIRST_LIMIT) Subs        $(TOP_X_SUBS_DATA_FILE))
$(info ** [Step 7] Top Sub no Pinyin Data  $(TOP_X_SUBS_NP_DATA_FILE))
$(info ** NUM PROCS $(NUM_PROCS))
$(info ** SORT OPTIONS $(SORT_MEMORY_LIMIT) $(SORT_MEMORY_FOLDER))

# Make an "all" target.
all: step7

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

# Take the top X subdomains
step6: $(TOP_X_SUBS_DATA_FILE)
$(TOP_X_SUBS_DATA_FILE): $(TOP_SUB_DATA_FILE)
	@echo "Step 6 (limit top subdomains): Creating $@ from $<"
	pv -cN input $< | \
		pigz -dc | \
		head -$(TOP_FIRST_LIMIT) | \
		pigz -c | \
		pv -cN output > $@

# Use the filterpinyin script to filter out domains which look like pinyin.
# This doesn't have to be perfect but we want to get rid of the most obvious ones.
step7: $(TOP_X_SUBS_NP_DATA_FILE)
$(TOP_X_SUBS_NP_DATA_FILE): $(TOP_X_SUBS_DATA_FILE)
	@echo "Step 7 (pinyin filtering): Creating $@ from $<"
	pv -cN input $< | \
		pigz -dc | \
		parallel --no-notice --pipe --line-buffer --block 1M python3 ./filterpinyinsub.py 2>$(TOP_X_SUBS_P_DATA_FILE) | \
		pigz -c | \
		pv -cN output > $@

# Make the results files
results/top1000000_count: $(TOP_X_SUBS_NP_DATA_FILE)
	@echo "Make top 1000000 with count"
	pv -cN input $< | \
                pigz -dc | \
                head -1000000 > $@

results/top100000_count: results/top1000000_count
	@echo "Make top 100000 with count"
	head -100000 < $< > $@

results/top10000_count: results/top100000_count
	@echo "Make top 10000 with count"
	head -10000 < $< > $@

results/top1000_count: results/top10000_count
	@echo "Make top 10000 with count"
	head -1000 < $< > $@

results/top1000000: results/top1000000_count
	@echo "Make top 1000000 without count"
	python3 ./uncount.py < $< > $@

results/top100000: results/top100000_count
	@echo "Make top 100000 without count"
	python3 ./uncount.py < $< > $@

results/top10000: results/top10000_count
	@echo "Make top 10000 without count"
	python3 ./uncount.py < $< > $@

results/top1000: results/top1000_count
	@echo "Make top 1000 without count"
	python3 ./uncount.py < $< > $@

top_results: results/top1000 results/top10000 results/top100000 results/top1000000

# Have a target to clean up all generated files
.PHONY: clean
clean:
	@rm -fv $(NAME_DATA_FILE) \
		$(SUB_DATA_FILE) \
		$(SORTED_SUB_DATA_FILE) \
		$(COUNTED_SUB_DATA_FILE)
