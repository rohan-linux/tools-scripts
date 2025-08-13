#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <termios.h>
#include <string.h>
#include <sys/select.h>
#include <errno.h>
#include <sys/stat.h>

#define SOH 0x01
#define EOT 0x04
#define ACK 0x06
#define NAK 0x15
#define CRC_POLY 0x1021

static uint16_t crc16(const uint8_t *data, size_t length)
{
	uint16_t crc = 0;

	for (size_t i = 0; i < length; i++) {
		crc ^= (uint16_t)data[i] << 8;
		for (int j = 0; j < 8; j++)
			crc = crc & 0x8000 ? (crc << 1) ^ CRC_POLY : crc << 1;
	}

	return crc;
}

static int set_serial(int fd)
{
	struct termios tty;

	memset(&tty, 0, sizeof tty);
	if (tcgetattr(fd, &tty) != 0) {
		perror("tcgetattr");
		return -1;
	}

	cfsetospeed(&tty, B115200);
	cfsetispeed(&tty, B115200);

	tty.c_cflag &= ~PARENB;  /* no parity */
	tty.c_cflag &= ~CSTOPB;  /* 1 stop bit */
	tty.c_cflag &= ~CSIZE;
	tty.c_cflag |= CS8;      /* 8-bit chars */
	tty.c_cflag &= ~CRTSCTS; /* no flow control */
	tty.c_cflag |= CREAD | CLOCAL;

	tty.c_lflag &= ~(ICANON | ECHO | ECHOE | ISIG);
	tty.c_iflag &= ~(IXON | IXOFF | IXANY | IGNBRK | BRKINT | PARMRK | ISTRIP | INLCR | IGNCR | ICRNL);
	tty.c_oflag &= ~OPOST;

	tty.c_cc[VMIN] = 1;
	tty.c_cc[VTIME] = 1;

	if (tcsetattr(fd, TCSANOW, &tty) != 0) {
		perror("tcsetattr");
		return -1;
	}
	return 0;
}

static int wait_for_C(int fd)
{
	uint8_t buf;

	while (1) {
		ssize_t r = read(fd, &buf, 1);

		if ((r > 0) && (buf == 'C'))
			return 0;

		usleep(100000);
	}
}

int xmodem_send(int fd, FILE *file)
{
	uint8_t packet[133], ack;
	uint8_t block_num = 1;
	uint8_t eot = EOT;
	size_t bytes_read, trans_size = 0;
	struct stat st;
	uint16_t crc;
	long start_pos;

	start_pos = ftell(file);
	if (start_pos == -1) {
		perror("ftell");
		return -1;
	}

	if (fstat(fileno(file), &st) == 0)
		if (st.st_size == 0) {
			fprintf(stderr, "Error: File size is 0 bytes.\n");
			return -1;
		}

	while (1) {
		bytes_read = fread(packet + 3, 1, 128, file);
		if (bytes_read == 0) {
			if (feof(file)) {
				break;
			} else if (ferror(file)) {
				perror("fread");
				return -1;
			} else {
				fprintf(stderr, "Unknown fread error\n");
				return -1;
			}
		}

		while (1) {
			fd_set fds;
			struct timeval tv;
			int sel;

			packet[0] = SOH;
			packet[1] = block_num;
			packet[2] = 0xff - block_num;
			memset(packet + 3 + bytes_read, 0x1A, 128 - bytes_read);

			crc = crc16(packet + 3, 128);

			packet[131] = crc >> 8;
			packet[132] = crc & 0xff;

			printf("\r Transfer %ld", trans_size);
			trans_size += bytes_read;

			if (write(fd, packet, 133) != 133) {
				perror("write(packet)");
				return -1;
			}

retry:
			FD_ZERO(&fds);
			FD_SET(fd, &fds);
			tv.tv_sec = 10;
			tv.tv_usec = 0;

			sel = select(fd + 1, &fds, NULL, NULL, &tv);
			if (sel == 0) {
				fprintf(stderr, "timeout !!!\n");
				goto retry;
			} else if (sel < 0) {
				fprintf(stderr, "error.%d !!!\n", sel);
				return -1;
			} else {
				ssize_t n = read(fd, &ack, 1);
				if (n > 0) {
					if (ack == ACK) {
						/* BLOCK NUMBER: [1] -> 2 -> ... -> 254 -> 255 -> [0] -> 1 ... */
						block_num++;
						break;
					} else if (ack == NAK) {
						continue;
					}
				}
			}
		}
	}

	printf("\n Transfer %ld completed\n", trans_size);

	if (write(fd, &eot, 1) != 1) {
		perror("write(EOT)");
		return -1;
	}

	return 0;
}

int main(int argc, char *argv[])
{
	FILE *file;
	char *fname, *dnode;
	int fd;

	if (argc != 3) {
		fprintf(stderr, "Usage: %s <tty> <fname>\n", argv[0]);
		exit(1);
	}

	dnode = argv[1];
	fname = argv[2];

	fd = open(dnode, O_RDWR | O_NOCTTY | O_SYNC);
	if (fd < 0) {
		perror("open tty");
		exit(1);
	}
	if (set_serial(fd) < 0) {
		close(fd);
		exit(1);
	}

	file = fopen(fname, "rb");
	if (!file) {
		perror("open file");
		close(fd);
		exit(1);
	}

	printf("Waiting for 0x43 (C)...\n");
	if (wait_for_C(fd) != 0) {
		fprintf(stderr, "Failed to receive 'C'.\n");
		fclose(file);
		close(fd);
		exit(1);
	}
	printf("Transferring: %s (%s)\n", fname, dnode);

	if (xmodem_send(fd, file) < 0)
		fprintf(stderr, "Transfer failed\n");

	fclose(file);
	close(fd);

	return 0;
}
