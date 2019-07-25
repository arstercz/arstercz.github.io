import java.net.*; 
 
public class hostrecv { 
     public static void main(String args[]) throws Exception { 
          while(true) { 
             InetAddress[] addresses = InetAddress 
                     .getAllByName(args[0]); 
             for (InetAddress addr : addresses) { 
                  System.out.println(addr); 
             } 
             System.out.println("\n"); 
             Thread.sleep(2000);
          }
    } 
}
