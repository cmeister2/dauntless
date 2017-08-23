TEST_DATA_FILE := ./testdns.json.gz
TEST_DATA_LINES := 500000
DATA_FILE ?= $(TEST_DATA_FILE)

$(info ** DATA FILE $(DATA_FILE))

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

# Extract the name field from the data set
NAME_DATA_FILE := $(dir $(DATA_FILE))name_$(notdir $(DATA_FILE))
$(info ** NAME DATA $(NAME_DATA_FILE))

create_name_data: $(NAME_DATA_FILE)
$(NAME_DATA_FILE): $(DATA_FILE)
	@echo "Creating $@ from $<"
	pv $< | pigz -dc | jq -r .name | pigz -c > $@


# Have a target to clean up all generated files
.PHONY: clean
clean:
	@rm -vf $(NAME_DATA_FILE)