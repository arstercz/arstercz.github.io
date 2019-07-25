#include <stdio.h>
#include <errno.h>
#include <netdb.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <arpa/nameser.h>
#include <resolv.h>

int main(int argc, char *argv[])
{
    int i;
    struct hostent *get;
    struct in_addr **addr_list;

    if (argc != 2) {
        fprintf(stderr,"usage: %s domainname\n", argv[0]);
        return 1;
    }
    while (1) {
        if ((get = gethostbyname(argv[1])) == NULL) {  // get the host info
            herror("gethostbyname");
            res_init();
            continue;
        }
        // print information about this host:
        printf("Official name is: %s\n", get->h_name);
        printf("    IP addresses: ");
        addr_list = (struct in_addr **)get->h_addr_list;
        for(i = 0; addr_list[i] != NULL; i++) {
            printf("%s ", inet_ntoa(*addr_list[i]));
        }
        printf("\n");
        sleep(2);
    }
    return 0;
}
