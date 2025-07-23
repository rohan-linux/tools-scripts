CROSS_COMPILE ?=
CC = $(CROSS_COMPILE)gcc
CFLAGS = -Wall -Wextra -O2 -static

BUILD_DIR ?= build
INSTALL_DIR ?= install 

SRCS := xmodem.c
OBJS := $(patsubst %.c,$(BUILD_DIR)/%.o,$(SRCS))

TARGET := xmodem

all: $(BUILD_DIR)/$(TARGET)

$(BUILD_DIR)/$(TARGET): $(OBJS)
	@mkdir -p $(@D)
	$(CC) $(CFLAGS) $^ -o $@

$(BUILD_DIR)/%.o: %.c	
	@mkdir -p $(@D)
	$(CC) $(CFLAGS) -c $< -o $@

install: $(BUILD_DIR)/$(TARGET)
	@mkdir -p $(INSTALL_DIR)
	install -m 755 $(BUILD_DIR)/$(TARGET) $(INSTALL_DIR)/$(TARGET)

clean:
	rm -rf $(BUILD_DIR)

.PHONY: all clean install
