/* touchfix - UJC201/AC8257 (TWRP)
 *  - tactile : mtk-tpd rapporte des coordonnees paysage ~1024x600 (X inverse) alors qu'il annonce 720x1280.
 *    On capture mtk-tpd (EVIOCGRAB) et on reemet sur un peripherique uinput "ujc201-touch".
 *    TWRP (ev_get) met l'axe X a l'echelle de la largeur affichee apres rotation, donc pas d'echange X/Y.
 *  - bandeau gauche (X brut > 1030) : zones power / home / back / vol+ / vol- -> touches.
 *  - reveil du tactile : ecriture de 0 dans fb0/blank (notification ecran allume, sans eteindre la dalle).
 *  - luminosite : TWRP ecrit 0..255 dans /tmp/twbl, pilote Jancar inverse (0 = max, 179 = min).
 *  - barre d'etat : /tmp/twcpu (temperature CPU + tension d'entree, 2 sondes ADC) ;
 *    MCU (ttyS1) : /tmp/twcar (ACC, frein a main, feux, version MCU), /tmp/mcu_version.
 *  - MCU : synchro de l'horloge, touches au volant (uinput "ujc201-wheel"), fenetres /tmp/twpopup.
 * Usage: touchfix [rawx rawy swap flipu flipv outw outh]   (defaut : 1024 600 0 1 0 720 1280)
 * Autonome (pas de libc) : syscalls aarch64 directs. */
typedef unsigned long u64; typedef long s64; typedef unsigned short u16; typedef int s32; typedef unsigned int u32; typedef short s16;
static s64 sys(s64 n,s64 a,s64 b,s64 c,s64 d){register s64 x8 asm("x8")=n,x0 asm("x0")=a,x1 asm("x1")=b,x2 asm("x2")=c,x3 asm("x3")=d;
 asm volatile("svc 0":"+r"(x0):"r"(x8),"r"(x1),"r"(x2),"r"(x3):"memory");return x0;}
#define SYS_openat 56
#define SYS_close 57
#define SYS_read 63
#define SYS_write 64
#define SYS_ioctl 29
#define SYS_nanosleep 101
#define SYS_exit 93
#define AT_FDCWD -100
#define O_RDWR 2
#define O_WRONLY 1
#define O_RDONLY 0
static int op(const char*p,int f){return (int)sys(SYS_openat,AT_FDCWD,(s64)p,f,0);}
static void msleep(int ms){s64 ts[2]={ms/1000,(ms%1000)*1000000L};sys(SYS_nanosleep,(s64)ts,0,0,0);}
static int slen(const char*s){int n=0;while(s[n])n++;return n;}
static void logs(const char*s){int fd=op("/tmp/touchfix.log",O_WRONLY|0100|02000);if(fd>=0){sys(SYS_write,fd,(s64)s,slen(s),0);sys(SYS_close,fd,0,0,0);}}
static int atoi_(const char*s){int n=0,g=1;if(*s=='-'){g=-1;s++;}while(*s>='0'&&*s<='9')n=n*10+(*s++-'0');return n*g;}
static int streq(const char*a,const char*b){while(*a&&*a==*b){a++;b++;}return *a==*b;}
/* ioctl numbers */
#define IOC(d,t,n,s) (((d)<<30)|((s)<<16)|((t)<<8)|(n))
#define EVIOCGNAME(len) IOC(2,'E',0x06,len)
#define EVIOCGRAB IOC(1,'E',0x90,4)
#define UI_SET_EVBIT IOC(1,'U',100,4)
#define UI_SET_KEYBIT IOC(1,'U',101,4)
#define UI_SET_ABSBIT IOC(1,'U',103,4)
#define UI_SET_PROPBIT IOC(1,'U',110,4)
#define UI_DEV_CREATE IOC(0,'U',1,0)
struct ev{s64 sec,usec;u16 type,code;s32 value;};
#define EV_SYN 0
#define EV_KEY 1
#define EV_ABS 3
#define SYN_REPORT 0
#define SYN_MT_REPORT 2
#define BTN_TOUCH 0x14a
#define ABS_X 0
#define ABS_Y 1
#define ABS_MT_TOUCH_MAJOR 0x30
#define ABS_MT_POSITION_X 0x35
#define ABS_MT_POSITION_Y 0x36
#define ABS_MT_TRACKING_ID 0x39
struct uidev{char name[80];u16 bustype,vendor,product,version;u32 ff;s32 absmax[64],absmin[64],absfuzz[64],absflat[64];};
static struct uidev ud;
static void emit(int fd,u16 t,u16 c,s32 v){struct ev e={0,0,t,c,v};sys(SYS_write,fd,(s64)&e,sizeof e,0);}
/* ---- barre d'etat TWRP : /tmp/twcpu (affiche tel quel par tw_cpu_temp patche) ---- */
static int rdint(const char*p){char b[32];int fd=op(p,O_RDONLY);if(fd<0)return -1;s64 n=sys(SYS_read,fd,(s64)b,31,0);sys(SYS_close,fd,0,0,0);if(n<=0)return -1;b[n]=0;return atoi_(b);}
static int soc_ch4(void){ /* ligne "[ 4,2466, 902]-..." de AUXADC_read_channel */
 static char b[1024];int fd=op("/sys/devices/virtual/mtk-adc-cali/mtk-adc-cali/AUXADC_read_channel",O_RDONLY);if(fd<0)return -1;
 s64 n=sys(SYS_read,fd,(s64)b,1023,0);sys(SYS_close,fd,0,0,0);if(n<=0)return -1;b[n]=0;
 for(int i=0;i<n;i++){if(b[i]=='['){int j=i+1;while(b[j]==' ')j++;if(b[j]=='4'&&b[j+1]==','){int c=0,k=j+2;while(k<n&&c<1){if(b[k]==',')c++;k++;}while(b[k]==' ')k++;return atoi_(b+k);}}}
 return -1;}
static char*pnum(char*o,int v){char t[12];int k=0;if(v<0){*o++='-';v=-v;}do{t[k++]='0'+v%10;v/=10;}while(v);while(k)*o++=t[--k];return o;}
static char*pstr(char*o,const char*s){while(*s)*o++=*s++;return o;}
static char*pvolt(char*o,int mv){ if(mv<0)return pstr(o,"--"); o=pnum(o,mv/1000);*o++='.';int c=(mv%1000)/10;*o++='0'+c/10;*o++='0'+c%10;*o++='V';return o;}
/* tableau de bord / barre d'etat TWRP : proprietes systeme "ujc201.<nom>", lues par le theme avec
 * %property.ujc201.<nom>% (DataManager::GetValue gere "property." : aucun patch du binaire TWRP).
 * Protocole init v2 : PROP_MSG_SETPROP2, <len>nom, <len>valeur sur /dev/socket/property_service. */
#define SYS_socket 198
#define SYS_connect 203
static struct{char k[12];u32 h;int ok;}pc[24];
static int setprop(const char*k,const char*v,int vl){
 int fd=(int)sys(SYS_socket,1/*AF_UNIX*/,1/*SOCK_STREAM*/|02000000/*CLOEXEC*/,0,0);if(fd<0)return -1;
 struct{u16 fam;char path[108];}sa;sa.fam=1;const char*sp="/dev/socket/property_service";int i=0;for(;sp[i];i++)sa.path[i]=sp[i];sa.path[i]=0;
 if(sys(SYS_connect,fd,(s64)&sa,2+i+1,0)<0){sys(SYS_close,fd,0,0,0);return -1;}
 unsigned char m[160];int n=0,kl=slen(k);u32 w[1];
 w[0]=0x00020001;for(int j=0;j<4;j++)m[n++]=((unsigned char*)w)[j];
 w[0]=(u32)kl;for(int j=0;j<4;j++)m[n++]=((unsigned char*)w)[j];for(int j=0;j<kl;j++)m[n++]=k[j];
 w[0]=(u32)vl;for(int j=0;j<4;j++)m[n++]=((unsigned char*)w)[j];for(int j=0;j<vl;j++)m[n++]=v[j];
 s32 r=-1;if(sys(SYS_write,fd,(s64)m,n,0)==n)sys(SYS_read,fd,(s64)&r,4,0);
 sys(SYS_close,fd,0,0,0);return r;}
static void dw(const char*nm,const char*v,int l){
 if(l>91)l=91;while(l>0&&(v[l-1]=='\n'||v[l-1]==' '))l--;
 u32 h=2166136261u;for(int i=0;i<l;i++)h=(h^(unsigned char)v[i])*16777619u;h^=(u32)l;
 int e=-1;for(int i=0;i<24;i++){if(pc[i].k[0]&&streq(pc[i].k,nm)){e=i;break;}if(e<0&&!pc[i].k[0]){e=i;}}
 if(e<0)e=0;if(!streq(pc[e].k,nm)){int i=0;for(;nm[i]&&i<11;i++)pc[e].k[i]=nm[i];pc[e].k[i]=0;pc[e].ok=0;}
 if(pc[e].ok&&pc[e].h==h)return;
 char k[32],*o=k;o=pstr(o,"ujc201.");o=pstr(o,nm);*o=0;
 if(setprop(k,v,l)==0){pc[e].h=h;pc[e].ok=1;}}
static void dwi(const char*n,int v){char t[16],*o=pnum(t,v);dw(n,t,(int)(o-t));}
static int seg10(int v,int lo,int hi){if(v<=lo)return 0;if(v>=hi)return 10;return (v-lo)*10/(hi-lo);}
static void status(void){
 char s[200],*o=s;int t=rdint("/sys/class/thermal/thermal_zone1/temp");
 /* sans le patch "texte" du binaire recovery (marqueur absent), TWRP attend un nombre : on ecrit la temperature brute */
 {int m=op("/system/etc/ujc201_statustext",O_RDONLY);if(m<0){o=pnum(o,t);*o++='\n';
   int fd=op("/tmp/twcpu",O_WRONLY|0100|01000);if(fd>=0){sys(SYS_write,fd,(s64)s,o-s,0);sys(SYS_close,fd,0,0,0);}return;} sys(SYS_close,m,0,0,0);}int a=soc_ch4();int v=rdint("/sys/bus/iio/devices/iio:device0/in_voltage2_VCDT_input");
 {int m1=a<0?-1:(int)((s64)a*12020/902),m2=v<0?-1:(int)((s64)v*12020/649);char b[16],*q;
  q=pvolt(b,m1);dw("vin1",b,(int)(q-b)-(m1>=0));q=pvolt(b,m2);dw("vin2",b,(int)(q-b)-(m2>=0));   /* sans le "V" */
  dwi("vinseg",m1<0?0:seg10(m1,9000,15000));
  if(t>0){dwi("cpu",t/1000);dwi("cpuseg",seg10(t/1000,30,90));}else{dw("cpu","--",2);dwi("cpuseg",0);}}
 o=pstr(o,"CPU: ");if(t>-100000){o=pnum(o,t/1000);o=pstr(o," \xC2\xB0""C");}else o=pstr(o,"--");
 /* calibration 12.02 V : ch4 902 mV (x13.33), VCDT 649 mV (x18.52) - a valider en voiture */
 o=pstr(o,"   Vin: ");o=pvolt(o,a<0?-1:(int)((s64)a*12020/902));o=pstr(o," | ");o=pvolt(o,v<0?-1:(int)((s64)v*12020/649));
 /* theme sans zone de droite (%tw_ujc201_car%) : etat vehicule compact a la suite */
 {int m=op("/system/etc/ujc201_carstatus",O_RDONLY);if(m>=0)sys(SYS_close,m,0,0,0);
  else{char c[48];int fd=op("/tmp/twcar_s",O_RDONLY);if(fd>=0){s64 n=sys(SYS_read,fd,(s64)c,47,0);sys(SYS_close,fd,0,0,0);
   if(n>0){c[n]=0;while(n>0&&c[n-1]=='\n')c[--n]=0;o=pstr(o,"   ");o=pstr(o,c);}}}}
 *o++='\n';
 /* ni fenetres TWRP (marqueur ujc201_popup) ni bandeau du theme (ujc201_banner) : titre en tete de ligne */
 {int m=op("/system/etc/ujc201_popup",O_RDONLY);if(m<0)m=op("/system/etc/ujc201_banner",O_RDONLY);if(m>=0)sys(SYS_close,m,0,0,0);
  else{char p[96];int fd=op("/tmp/twpopup",O_RDONLY);if(fd>=0){s64 n=sys(SYS_read,fd,(s64)p,95,0);sys(SYS_close,fd,0,0,0);
   if(n>2&&p[1]=='\t'){char t[200],*q=t;q=pstr(q,"[");for(int i=2;i<n&&p[i]!='\t'&&p[i]!='\n';i++)*q++=p[i];q=pstr(q,"]  ");
    for(char*r=s;r<o;)*q++=*r++;int l=(int)(q-t);if(l>190)l=190;for(int i=0;i<l;i++)s[i]=t[i];o=s+l;}}}}
 int fd=op("/tmp/twcpu",O_WRONLY|0100|01000);if(fd>=0){sys(SYS_write,fd,(s64)s,o-s,0);sys(SYS_close,fd,0,0,0);}
}

/* ---- MCU Jancar (protocole JAC_V1, /dev/ttyS1 115200) ----
 * trame : EE FA <len=donnees+1> <cmd> <donnees> <somme de tous les octets precedents>
 * envoi : 0x1F 01 (PC_READY, comme Android au demarrage ; pas de battement de coeur sur AC8257), 0xF0 00 00 (etat ACC)
 * recu  : 0x00 ACC, 0x04 frein a main, 0x0B feux (ILL), 0x1F etat groupe (b6 frein, b4 feux), 0x0A version (texte),
 *         0x09 date [0,aa/100,aa%100,mois,jour] / heure [1,h,m,s] (heure LOCALE), 0x20 touche [canal,v1,v2,v3,v4]
 *         (canal 1 telecommande IR, 2 molette, 3/4 touches AD, 5/6 volant ; relache = 0xFF), 0x10 octets du boitier CAN
 *         (Hiworld : touches au volant sur le canal 7, voir hw_feed).
 * sorties : /tmp/twcar (barre d'etat, a droite : ACC, frein, feux ; version -> Advanced > MCU info), /tmp/twcar_s (compact), /tmp/mcu_version, /tmp/mcu_time,
 *           /tmp/mcu_key ("seq canal v1 v2 v3 v4", pour wheelkeys), /tmp/twpopup (fenetres dessinees par TWRP),
 *           peripherique uinput "ujc201-wheel" (touches au volant -> touches TWRP, table ujc201_keys.conf) */
#define TCGETS 0x5401
#define TCSETS 0x5402
#define SYS_newfstatat 79
#define SYS_clock_gettime 113
#define SYS_gettimeofday 169
#define SYS_settimeofday 170
struct ktermios{u32 c_iflag,c_oflag,c_cflag,c_lflag;unsigned char c_line,c_cc[19];};
static int m_acc=-1,m_hb=-1,m_ill=-1;static char m_ver[40];
static s64 now_ms(void){s64 ts[2];sys(SYS_clock_gettime,1/*MONOTONIC*/,(s64)ts,0,0);return ts[0]*1000+ts[1]/1000000;}
static int exists(const char*p){int f=op(p,O_RDONLY);if(f<0)return 0;sys(SYS_close,f,0,0,0);return 1;}
static void mcu_log(const char*tag,const unsigned char*f,int n);
static void mcu_send(int fd,unsigned char cmd,const unsigned char*d,int n){unsigned char f[32];int k=0,sum=0;
 f[k++]=0xEE;f[k++]=0xFA;f[k++]=(unsigned char)(n+1);f[k++]=cmd;for(int i=0;i<n;i++)f[k++]=d[i];
 for(int i=0;i<k;i++)sum+=f[i];f[k++]=(unsigned char)sum;sys(SYS_write,fd,(s64)f,k,0);mcu_log("tx",f,k);}
static void wrtxt(const char*p,const char*s,int n){int fd=op(p,O_WRONLY|0100|01000);if(fd>=0){sys(SYS_write,fd,(s64)s,n,0);sys(SYS_close,fd,0,0,0);}}
static char*onoff(char*o,int v){return pstr(o,v<0?"--":v?"ON":"OFF");}
static char*p2(char*o,int v){*o++='0'+(v/10)%10;*o++='0'+v%10;return o;}
static char*phex(char*o,int v){const char*h="0123456789ABCDEF";*o++=h[(v>>4)&15];*o++=h[v&15];return o;}
static void mcu_publish(void){char s[128],*o=s;
 o=pstr(o,"ACC ");o=onoff(o,m_acc);o=pstr(o,"   HB ");o=onoff(o,m_hb);o=pstr(o,"   LIGHTS ");o=onoff(o,m_ill);
 dw("car",s,(int)(o-s));*o++='\n';wrtxt("/tmp/twcar",s,o-s);
 {char b[8],*q;q=onoff(b,m_acc);dw("acc",b,(int)(q-b));q=onoff(b,m_hb);dw("hb",b,(int)(q-b));q=onoff(b,m_ill);dw("ill",b,(int)(q-b));}
 if(m_ver[0])dw("mcuver",m_ver,slen(m_ver));else dw("mcuver","no answer from MCU",18);
 o=s;o=pstr(o,"ACC:");o=onoff(o,m_acc);o=pstr(o," HB:");o=onoff(o,m_hb);o=pstr(o," ILL:");o=onoff(o,m_ill);*o++='\n';wrtxt("/tmp/twcar_s",s,o-s);}
static int m_nlog;
static void mcu_log(const char*tag,const unsigned char*f,int n){if(m_nlog>=1500)return;m_nlog++;
 char s[600],*o=s;const char*hx="0123456789abcdef";o=pstr(o,tag);for(int i=0;i<n&&i<180;i++){*o++=' ';*o++=hx[f[i]>>4];*o++=hx[f[i]&15];}*o++='\n';
 int fd=op("/tmp/mcu.log",O_WRONLY|0100|02000);if(fd>=0){sys(SYS_write,fd,(s64)s,o-s,0);sys(SYS_close,fd,0,0,0);}}

/* -- horloge : trame 0x09 (heure locale du MCU) --
 * TWRP patche (marqueur /system/etc/ujc201_popup) : il lit /tmp/mcu_time et regle l'horloge avec mktime() dans
 * son fuseau (tw_time_zone). Sinon (binaire non patche) : on corrige ici la derive en gardant le decalage
 * horaire deja present (ecart MCU - systeme arrondi au 1/4 d'heure) ; horloge systeme invalide (< 2024) -> heure MCU. */
static int c_Y,c_M,c_D,c_ok;
static s64 civil_days(int y,int m,int d){y-=m<=2;s64 era=(y>=0?y:y-399)/400;s64 yoe=y-era*400;s64 doy=(153*(m+(m>2?-3:9))+2)/5+d-1;
 s64 doe=yoe*365+yoe/4-yoe/100+doy;return era*146097+doe-719468;}
static void mcu_clock(int h,int mi,int se){
 if(!c_ok||c_Y<2024||c_Y>2099||c_M<1||c_M>12||c_D<1||c_D>31||h>23||mi>59||se>59)return;
 char s[48],*o=s;o=pnum(o,c_Y);*o++='-';o=p2(o,c_M);*o++='-';o=p2(o,c_D);*o++=' ';o=p2(o,h);*o++=':';o=p2(o,mi);*o++=':';o=p2(o,se);
 dw("mcutime",s,(int)(o-s));*o++=' ';o=pnum(o,(int)now_ms());*o++='\n';wrtxt("/tmp/mcu_time",s,o-s);
 if(exists("/system/etc/ujc201_popup"))return;                 /* TWRP s'en charge (fuseau exact) */
 s64 loc=civil_days(c_Y,c_M,c_D)*86400+h*3600+mi*60+se;        /* heure locale comptee comme UTC */
 s64 tv[2];sys(SYS_gettimeofday,(s64)tv,0,0,0);s64 d=loc-tv[0],nt=0;
 if(tv[0]<1704067200)nt=loc;                                   /* horloge systeme invalide */
 else{s64 off=(d>=0?d+450:d-450)/900*900;if(off>14*3600||off< -14*3600)return;s64 dr=d-off;if(dr>=3||dr<=-3)nt=tv[0]+dr;}
 if(nt){s64 t2[2]={nt,0};s64 r=sys(SYS_settimeofday,(s64)t2,0,0,0);logs(r==0?"touchfix: horloge corrigee (MCU)\n":"touchfix: settimeofday refuse\n");}}

/* -- touches au volant : table <canal> <octet 1..4> <min> <max> <action> [nom] -- */
#define NMAP 32
struct kmap{unsigned char ch,idx,lo,hi;signed char act;char name[14];};
static struct kmap km[NMAP+1];static int nkm;   /* km[NMAP] : touche du boitier CAN sans ligne dans la table */
static const struct{const char*n;s16 code;const char*label;}acts[]={
 {"volup",115,"Volume +"},{"voldown",114,"Volume -"},{"enter",28,"Enter"},{"back",158,"Back"},{"home",172,"Home"},
 {"power",116,"Screen / lock"},{"up",103,"Up"},{"down",108,"Down"},{"left",105,"Left"},{"right",106,"Right"},
 {"bl+",-1,"Brightness +"},{"bl-",-2,"Brightness -"},{"none",0,"popup only"}};
#define NACT ((int)(sizeof acts/sizeof acts[0]))
static const char*kcfg[3]={"/data/media/0/TWRP/ujc201_keys.conf","/tmp/ujc201_keys.conf","/system/etc/ujc201_keys.conf"};
static s64 kcfg_sig=-1;
static int tok(char**p,char*out,int max){char*s=*p;while(*s==' '||*s=='\t')s++;int n=0;while(*s&&*s!=' '&&*s!='\t'&&*s!='\n'&&*s!='\r'){if(n<max-1)out[n++]=*s;s++;}out[n]=0;*p=s;return n;}
static void keys_load(void){
 s64 st[16];int w=-1;for(int i=0;i<3&&w<0;i++)if(sys(SYS_newfstatat,AT_FDCWD,(s64)kcfg[i],(s64)st,0)==0)w=i;
 s64 sig=w<0?0:(w+1)+st[6]*7+st[11]*131+st[12];if(sig==kcfg_sig)return;kcfg_sig=sig;nkm=0;if(w<0){dwi("keymap",0);return;}
 static char b[4096];int fd=op(kcfg[w],O_RDONLY);if(fd<0)return;s64 n=sys(SYS_read,fd,(s64)b,4095,0);sys(SYS_close,fd,0,0,0);if(n<=0)return;b[n]=0;
 for(char*l=b;*l&&nkm<NMAP;){char*e=l;while(*e&&*e!='\n')e++;char c=*e;*e=0;
  char t[5][16];char*q=l;int k=0;while(k<5&&tok(&q,t[k],16))k++;
  if(k==5&&t[0][0]!='#'){struct kmap*m=&km[nkm];m->ch=(unsigned char)atoi_(t[0]);m->idx=(unsigned char)atoi_(t[1]);m->lo=(unsigned char)atoi_(t[2]);m->hi=(unsigned char)atoi_(t[3]);
   m->act=-1;for(int a=0;a<NACT;a++)if(streq(t[4],acts[a].n))m->act=(signed char)a;
   char nm[16];if(!tok(&q,nm,14)){int i=0;for(;t[4][i]&&i<13;i++)nm[i]=t[4][i];nm[i]=0;}for(int i=0;i<14;i++)m->name[i]=nm[i];
   if(m->act>=0&&m->idx>=1&&m->idx<=4)nkm++;}
  *e=c;l=*e?e+1:e;}
 dwi("keymap",nkm);
 char s[64],*o=s;o=pstr(o,"touchfix: touches volant : ");o=pnum(o,nkm);o=pstr(o," (");o=pstr(o,kcfg[w]);o=pstr(o,")\n");logs(s);}
static int hw_default(int code);
static int kfd=-1,k_held,k_map=-1,k_seq;static s64 k_last,k_hide;static char k_popup[160];
static void key_emit(int code,int v){if(kfd<0||code<=0)return;emit(kfd,EV_KEY,(u16)code,v);emit(kfd,EV_SYN,SYN_REPORT,0);}
static void bl_step(int dir){int v=rdint("/tmp/twbl");if(v<0)v=180;v+=dir*32;if(v<16)v=16;if(v>255)v=255;char t[8];char*o=pnum(t,v);*o++='\n';wrtxt("/tmp/twbl",t,o-t);}
static void wheel_dev(void){
 for(int i=0;i<30&&kfd<0;i++){kfd=op("/dev/uinput",O_RDWR);if(kfd<0)kfd=op("/dev/input/uinput",O_RDWR);if(kfd<0)msleep(100);}
 if(kfd<0)return;
 sys(SYS_ioctl,kfd,UI_SET_EVBIT,EV_KEY,0);sys(SYS_ioctl,kfd,UI_SET_EVBIT,EV_SYN,0);
 for(int a=0;a<NACT;a++)if(acts[a].code>0)sys(SYS_ioctl,kfd,UI_SET_KEYBIT,acts[a].code,0);
 static struct uidev w;const char*nm="ujc201-wheel";for(int i=0;nm[i];i++)w.name[i]=nm[i];
 w.bustype=0x19;w.vendor=0x2be1;w.product=0x0912;w.version=1;sys(SYS_write,kfd,(s64)&w,sizeof w,0);
 if(sys(SYS_ioctl,kfd,UI_DEV_CREATE,0,0)<0){sys(SYS_close,kfd,0,0,0);kfd=-1;logs("touchfix: uinput volant echec\n");}}
static void key_release(void){if(k_held&&k_map>=0)key_emit(acts[km[k_map].act].code,0);if(k_held)k_hide=now_ms()+1500;k_held=0;k_map=-1;}
static void mcu_key(const unsigned char*d,int dl){
 if(dl<2)return;int ch=d[0];unsigned char v[5]={0,d[1],dl>2?d[2]:255,dl>3?d[3]:255,dl>4?d[4]:255};
 int rel=ch==1?v[2]==255:ch==7?v[1]==255:(ch>=5?(v[2]==255&&v[3]==255&&v[4]==255):v[1]==255);
 if(rel){key_release();return;}
 k_last=now_ms();if(k_held)return;                      /* repetition pendant l'appui */
 k_held=1;k_hide=0;k_seq++;
 {char s[48],*o=s;o=pnum(o,k_seq);for(int i=0;i<5;i++){*o++=' ';o=pnum(o,i?v[i]:ch);}*o++='\n';wrtxt("/tmp/mcu_key",s,o-s);}
 keys_load();k_map=-1;for(int i=0;i<nkm;i++)if(km[i].ch==ch&&v[km[i].idx]>=km[i].lo&&v[km[i].idx]<=km[i].hi){k_map=i;break;}
 if(k_map<0&&ch==7)k_map=hw_default(v[1]);              /* boitier CAN : table Hiworld par defaut */
 char*o=k_popup;o=pstr(o,"K\t");
 if(k_map>=0){const struct kmap*m=&km[k_map];int a=m->act;o=pstr(o,"Steering wheel: ");o=pstr(o,m->name);o=pstr(o,"\tAction: ");o=pstr(o,acts[a].label);
  if(acts[a].code>0)key_emit(acts[a].code,1);else if(acts[a].code<0)bl_step(acts[a].code==-1?1:-1);}
 else{o=pstr(o,"Steering wheel: unknown key\tch ");o=pnum(o,ch);o=pstr(o," \xC2\xB7 ");for(int i=1;i<5;i++){o=phex(o,v[i]);*o++=' ';}
  o=pstr(o,"\xC2\xB7 Advanced > Steering wheel keys");}
 *o++='\n';*o=0;
 {char b[64],*q=b;if(k_map>=0){q=pstr(q,km[k_map].name);q=pstr(q," \xC2\xB7 ");q=pstr(q,acts[km[k_map].act].label);}
  else{q=pstr(q,"ch ");q=pnum(q,ch);for(int i=1;i<5;i++){*q++=' ';q=phex(q,v[i]);}q=pstr(q," (?)");}dw("key",b,(int)(q-b));}}
/* -- fenetres : /tmp/twpopup, une ligne par fenetre "<W|K|I>\t<titre>\t<texte>" (dessinees par TWRP patche) -- */
static s64 w_until;static int w_prev=-1;static char pop_last[512];
static void popup_update(void){
 s64 t=now_ms();char s[512],*o=s;
 if(k_held&&t-k_last>4000)key_release();               /* trame de relache perdue */
 if(m_ill==1&&w_prev!=1)w_until=t+8000;w_prev=m_ill;
 if(m_ill==1&&(m_acc==0||t<w_until)){
  if(m_acc==0)o=pstr(o,"W\tLights ON \xE2\x80\x94 ignition OFF\tBattery drain risk: switch the headlights off\n");
  else o=pstr(o,"W\tLights ON\tHeadlights / ILL wire detected by the MCU\n");}
 {static char b[200];int fd=op("/tmp/wheelkeys.prompt",O_RDONLY);       /* invite de wheelkeys learn */
  if(fd>=0){s64 n=sys(SYS_read,fd,(s64)b,190,0);sys(SYS_close,fd,0,0,0);if(n>0){b[n]=0;while(n>0&&b[n-1]=='\n')b[--n]=0;o=pstr(o,"I\t");o=pstr(o,b);*o++='\n';}}}
 if(k_held||t<k_hide)o=pstr(o,k_popup);
 *o=0;if(streq(s,pop_last))return;for(int i=0;i<=o-s;i++)pop_last[i]=s[i];wrtxt("/tmp/twpopup",s,o-s);
 /* bandeau du theme (binaire sans fenetres) : une seule ligne, priorite invite > touche > avertissement */
 const char*l=0;for(const char*pr="IKW";*pr&&!l;pr++)for(const char*q=s;*q;){if(q[0]==*pr&&q[1]=='\t'){l=q;break;}while(*q&&*q!='\n')q++;if(*q)q++;}
 if(!l){dw("pop_k","",0);dw("pop_t","",0);dw("pop_x","",0);return;}
 const char*ti=l+2,*te=ti;while(*te&&*te!='\t'&&*te!='\n')te++;
 const char*xs=te,*xe=te;if(*te=='\t'){xs=te+1;xe=xs;while(*xe&&*xe!='\n')xe++;}
 dw("pop_t",ti,(int)(te-ti));dw("pop_x",xs,(int)(xe-xs));dw("pop_k",l,1);}
/* -- boitier CAN Hiworld (Renault LNP002 : Clio 3...) relaye par le MCU en trames 0x10 --
 * Le MCU recopie les octets du boitier (USART1, 38400 par defaut) par paquets d'au plus 128 octets : un message peut
 * etre coupe en deux. Trame Hiworld : 5A A5 LEN CMD D0..Dn-1 CS, CS = ((LEN+CMD+somme D) & 0xFF) - 1.
 * Touche au volant : message 0x11, D1 bit 3 = evenement, D2 = code, D3 = 1 sur la trame d'appui ; un appui donne
 * 08 kk 01 / 08 kk 00 / 08 00 00 / 00 00 00 (~100 ms), maintenu : la sequence se repete (~380 ms).
 * Les touches passent par mcu_key() sur le canal 7 (v1 = code, relache = 255) : table, apprentissage, fenetres. */
static int hw_st,hw_len,hw_cmd,hw_pos,hw_down;static unsigned char hw_buf[64];
static const struct{unsigned char code;const char*act,*name;}hw_keys[]={
 {1,"volup","VOL+"},{2,"voldown","VOL-"},{3,"enter","MUTE"},{18,"enter","MUTE"},{15,"enter","OK"},{19,"enter","ANSWER"},
 {13,"up","PREV"},{5,"up","PREV"},{14,"down","NEXT"},{6,"down","NEXT"},{8,"right","RIGHT"},{9,"left","LEFT"},
 {10,"back","MODE"},{20,"back","HANG UP"},{4,"home","NAVI"}};
static int hw_default(int code){
 for(int pass=0;pass<2;pass++){int c=pass?code&0x1F:code;if(pass&&code<=0x1F)break;   /* code complet, puis 5 bits bas */
  for(unsigned i=0;i<sizeof hw_keys/sizeof hw_keys[0];i++)if(hw_keys[i].code==c){
   struct kmap*m=&km[NMAP];m->ch=7;m->idx=1;m->lo=m->hi=(unsigned char)code;m->act=-1;
   for(int a=0;a<NACT;a++)if(streq(hw_keys[i].act,acts[a].n))m->act=(signed char)a;
   int k=0;for(;hw_keys[i].name[k]&&k<13;k++)m->name[k]=hw_keys[i].name[k];m->name[k]=0;
   return m->act>=0?NMAP:-1;}}
 return -1;}
static int hw_frames;
static void hw_frame(int ok){
 dwi("canframes",++hw_frames);
 if(!ok||hw_cmd!=0x11||hw_len<4)return;
 int key=hw_buf[2],down=(hw_buf[1]&0x08)&&key&&hw_buf[3]==1;
 if(hw_down&&(!down||hw_down!=key)){unsigned char r[2]={7,255};mcu_key(r,2);hw_down=0;}
 if(down&&hw_down!=key){unsigned char p[2]={7,(unsigned char)key};mcu_key(p,2);hw_down=key;}
 popup_update();}
static void hw_feed(int v){
 switch(hw_st){
 case 0:if(v==0x5A)hw_st=1;break;
 case 1:hw_st=v==0xA5?2:v==0x5A?1:0;break;
 case 2:hw_len=v;hw_st=v>(int)sizeof hw_buf?0:3;break;
 case 3:hw_cmd=v;hw_pos=0;hw_st=hw_len?4:5;break;
 case 4:hw_buf[hw_pos++]=(unsigned char)v;if(hw_pos==hw_len)hw_st=5;break;
 default:{int sum=hw_len+hw_cmd;for(int i=0;i<hw_len;i++)sum+=hw_buf[i];hw_frame(v==(((sum&0xFF)-1)&0xFF));hw_st=0;}}}
static int m_frames;
static void mcu_frame(const unsigned char*f,int n){unsigned char cmd=f[3];const unsigned char*d=f+4;int dl=f[2]-1;static int can_logged;
 if(cmd!=0x10||can_logged++<200)mcu_log("rx",f,n);      /* boitier CAN : frequent, 200 trames au plus dans le journal */
 dwi("frames",++m_frames);
 if(cmd==0x00&&dl>=1)m_acc=d[0]==1;
 else if(cmd==0x04&&dl>=1)m_hb=d[0]==1;
 else if(cmd==0x0B&&dl>=1)m_ill=d[0]==1;
 else if(cmd==0x1F&&dl>=1){m_hb=(d[0]>>6)&1;m_ill=(d[0]>>4)&1;}
 else if(cmd==0x0A&&dl>0){int k=dl<39?dl:39;for(int i=0;i<k;i++)m_ver[i]=(d[i]>=32&&d[i]<127)?d[i]:'?';m_ver[k]=0;
  while(k>0&&m_ver[k-1]==' ')m_ver[--k]=0;
  char t[48];for(int i=0;i<=k;i++)t[i]=m_ver[i];t[k]='\n';wrtxt("/tmp/mcu_version",t,k+1);}
 else if(cmd==0x09&&dl>=4){if(d[0]==0&&dl>=5){c_Y=d[1]*100+d[2];c_M=d[3];c_D=d[4];c_ok=1;}else if(d[0]==1)mcu_clock(d[1],d[2],d[3]);return;}
 else if(cmd==0x20){mcu_key(d,dl);popup_update();return;}
 else if(cmd==0x10){for(int i=0;i<dl;i++)hw_feed(d[i]);return;}   /* octets du boitier CAN */
 else return;
 (void)n;mcu_publish();popup_update();}
static void mcu_loop(void){
 wrtxt("/tmp/twpopup","",0);
 wheel_dev();                                            /* avant le demarrage de TWRP (scan /dev/input) */
 dw("key","none yet",8);dwi("frames",0);dw("mcutime","--",2);dwi("keymap",0);
 mcu_publish();keys_load();
 int fd=-1;for(int t=0;t<100&&fd<0;t++){fd=op("/dev/ttyS1",O_RDWR|0400/*NOCTTY*/|04000/*NONBLOCK*/);if(fd<0)msleep(100);}
 if(fd<0){logs("touchfix: /dev/ttyS1 introuvable\n");sys(SYS_exit,0,0,0,0);}
 struct ktermios tio;if(sys(SYS_ioctl,fd,TCGETS,(s64)&tio,0)==0){
  tio.c_iflag=0;tio.c_oflag=0;tio.c_lflag=0;
  tio.c_cflag=(tio.c_cflag&~(0010017u/*CBAUD*/|0000060u/*CSIZE*/|0000400u/*PARENB*/|0000100u/*CSTOPB*/|020000000000u/*CRTSCTS*/))|0010002u/*B115200*/|0000060u/*CS8*/|0000200u/*CREAD*/|0004000u/*CLOCAL*/;
  tio.c_cc[6]=0;tio.c_cc[5]=0;sys(SYS_ioctl,fd,TCSETS,(s64)&tio,0);}
 logs("touchfix: MCU ttyS1 ouvert\n");
 const unsigned char ready[1]={1},qacc[2]={0,0},qhb[2]={4,0},qill[2]={0x0B,0};   /* F0 04 00 frein a main, F0 0B 00 feux (gestionnaire F0 du firmware MCU) */
 unsigned char buf[512];int bl=0,tries=0;s64 tick=0;
 for(;;){
  if(!m_ver[0]&&tries<3&&(tick%40)==0){mcu_send(fd,0x1F,ready,1);msleep(50);mcu_send(fd,0xF0,qacc,2);msleep(50);mcu_send(fd,0xF0,qhb,2);msleep(50);mcu_send(fd,0xF0,qill,2);tries++;}
  if(m_acc<0&&tick>0&&(tick%100)==0)mcu_send(fd,0xF0,qacc,2);
  if(m_hb<0&&tick>0&&(tick%100)==50)mcu_send(fd,0xF0,qhb,2);
  if(m_ill<0&&tick>0&&(tick%100)==75)mcu_send(fd,0xF0,qill,2);
  if((tick%20)==0)keys_load();
  s64 n=sys(SYS_read,fd,(s64)(buf+bl),sizeof buf-bl,0);
  if(n>0){bl+=(int)n;
   for(;;){int i=0;while(i+1<bl&&!(buf[i]==0xEE&&buf[i+1]==0xFA))i++;
    if(i>0){for(int j=i;j<bl;j++)buf[j-i]=buf[j];bl-=i;}
    if(bl<5)break;int tot=buf[2]+4;if(tot<5||tot>255){for(int j=1;j<bl;j++)buf[j-1]=buf[j];bl--;continue;}
    if(bl<tot)break;int sum=0;for(int j=0;j<tot-1;j++)sum+=buf[j];
    if((unsigned char)sum==buf[tot-1])mcu_frame(buf,tot);else mcu_log("bad",buf,tot);
    for(int j=tot;j<bl;j++)buf[j-tot]=buf[j];bl-=tot;}
   if(bl>=(int)sizeof buf)bl=0;}
  else msleep(50);
  popup_update();
  tick++;}
}

/* luminosite : TWRP ecrit 0..255 dans /tmp/twbl ; le pilote Jancar est inverse (0 = max, 179 = min) */
#define SYS_clone 220
static void bl_loop(void){
 char buf[16];int last=-1,tick=0;s64 psig=0;
 for(;;){ s64 sig=0;{char p[96];int fd=op("/tmp/twpopup",O_RDONLY);if(fd>=0){s64 n=sys(SYS_read,fd,(s64)p,95,0);sys(SYS_close,fd,0,0,0);
     for(int i=0;i<n;i++)sig=sig*31+p[i];sig+=n;}}
  if((tick++%7)==0||sig!=psig){psig=sig;status();}int fd=op("/tmp/twbl",O_RDONLY);
  if(fd>=0){s64 n=sys(SYS_read,fd,(s64)buf,15,0);sys(SYS_close,fd,0,0,0);
   if(n>0){buf[n]=0;int v=atoi_(buf);if(v<0)v=0;if(v>255)v=255;
    if(v!=last){last=v;int r=179-v*179/255;char o[8];int k=0;
     if(r>=100)o[k++]='0'+r/100; if(r>=10)o[k++]='0'+(r/10)%10; o[k++]='0'+r%10;
     int b=op("/sys/class/leds/lcd-backlight/brightness",O_WRONLY);if(b>=0){sys(SYS_write,b,(s64)o,k,0);sys(SYS_close,b,0,0,0);}}}}
  msleep(150);}
}
void start_c(s64*sp){
 int argc=(int)sp[0];char**argv=(char**)(sp+1);
 int rawx=1024,rawy=600,swap=0,flipu=1,flipv=0,ow=720,oh=1280;
 if(argc>=8){rawx=atoi_(argv[1]);rawy=atoi_(argv[2]);swap=atoi_(argv[3]);flipu=atoi_(argv[4]);flipv=atoi_(argv[5]);ow=atoi_(argv[6]);oh=atoi_(argv[7]);}
 logs("touchfix: start\n");
 status();
 {int f=op("/tmp/twbl",O_WRONLY|0100|01000);if(f>=0){sys(SYS_write,f,(s64)"180",3,0);sys(SYS_close,f,0,0,0);}}
 if(sys(SYS_clone,17/*SIGCHLD*/,0,0,0)==0){bl_loop();}
 if(sys(SYS_clone,17/*SIGCHLD*/,0,0,0)==0){mcu_loop();}
 /* 1. peripherique virtuel (avant TWRP) */
 int u=-1;for(int i=0;i<50&&u<0;i++){u=op("/dev/uinput",O_RDWR);if(u<0)u=op("/dev/input/uinput",O_RDWR);if(u<0)msleep(100);}
 if(u<0){logs("touchfix: pas de /dev/uinput\n");sys(SYS_exit,1,0,0,0);}
 sys(SYS_ioctl,u,UI_SET_EVBIT,EV_KEY,0);sys(SYS_ioctl,u,UI_SET_EVBIT,EV_ABS,0);sys(SYS_ioctl,u,UI_SET_EVBIT,EV_SYN,0);
 sys(SYS_ioctl,u,UI_SET_KEYBIT,BTN_TOUCH,0);{int ks[]={116,172,158,115,114};for(int i=0;i<5;i++)sys(SYS_ioctl,u,UI_SET_KEYBIT,ks[i],0);}sys(SYS_ioctl,u,UI_SET_PROPBIT,1/*INPUT_PROP_DIRECT*/,0);
 int abs_[]={ABS_X,ABS_Y,ABS_MT_TOUCH_MAJOR,ABS_MT_POSITION_X,ABS_MT_POSITION_Y,ABS_MT_TRACKING_ID};
 for(int i=0;i<6;i++)sys(SYS_ioctl,u,UI_SET_ABSBIT,abs_[i],0);
 const char*nm="ujc201-touch";for(int i=0;nm[i];i++)ud.name[i]=nm[i];
 ud.bustype=0x19;ud.vendor=0x2be1;ud.product=0x0911;ud.version=1;
 ud.absmax[ABS_X]=ow-1;ud.absmax[ABS_Y]=oh-1;ud.absmax[ABS_MT_POSITION_X]=ow-1;ud.absmax[ABS_MT_POSITION_Y]=oh-1;
 ud.absmax[ABS_MT_TOUCH_MAJOR]=255;ud.absmax[ABS_MT_TRACKING_ID]=10;
 sys(SYS_write,u,(s64)&ud,sizeof ud,0);
 if(sys(SYS_ioctl,u,UI_DEV_CREATE,0,0)<0){logs("touchfix: UI_DEV_CREATE echec\n");sys(SYS_exit,1,0,0,0);}
 logs("touchfix: uinput cree\n");
 /* 2. trouver mtk-tpd */
 int in=-1;char path[]="/dev/input/eventX";char name[64];
 for(int t=0;t<200&&in<0;t++){for(int i=0;i<10&&in<0;i++){path[16]='0'+i;int fd=op(path,O_RDONLY);if(fd<0)continue;
   for(int k=0;k<64;k++)name[k]=0;sys(SYS_ioctl,fd,EVIOCGNAME(63),(s64)name,0);
   if(streq(name,"mtk-tpd"))in=fd;else sys(SYS_close,fd,0,0,0);} if(in<0)msleep(100);}
 if(in<0){logs("touchfix: mtk-tpd introuvable\n");sys(SYS_exit,1,0,0,0);}
 sys(SYS_ioctl,in,EVIOCGRAB,1,0);
 logs("touchfix: mtk-tpd capture\n");
 /* 3. reveiller le tactile (notification ecran allume, sans eteindre la dalle) */
 msleep(1500);{int b=op("/sys/class/graphics/fb0/blank",O_WRONLY);if(b>=0){sys(SYS_write,b,(s64)"0",1,0);sys(SYS_close,b,0,0,0);logs("touchfix: unblank envoye\n");}}
 /* 4. boucle : trames buffereesjusqu'a SYN_REPORT */
 /* bandeau gauche : X brut > KEYX ; zones Y -> touches (power, home, back, vol+, vol-) */
 const int KEYX=1030; const int ylo[5]={55,148,230,313,392}, yhi[5]={148,230,313,392,480};
 const u16 kc[5]={116,172,158,115,114};
 struct ev e[64],fr[128];int nf=0;s32 rx=0,ry=0;int got=0,contact=0,held=-1;
 for(;;){s64 n=sys(SYS_read,in,(s64)e,sizeof e,0);if(n<=0){msleep(50);continue;}
  for(int i=0;i<(int)(n/sizeof(struct ev));i++){struct ev*p=&e[i];
   if(p->type==EV_ABS&&(p->code==ABS_MT_POSITION_X||p->code==ABS_X)){rx=p->value;got=1;contact=1;continue;}
   if(p->type==EV_ABS&&(p->code==ABS_MT_POSITION_Y||p->code==ABS_Y)){ry=p->value;got=1;continue;}
   if(!(p->type==EV_SYN&&p->code==SYN_REPORT)){
     if(p->type==EV_SYN&&p->code==SYN_MT_REPORT){ /* point : on range la position transformee dans la trame */
       if(got&&nf<124){s64 a=swap?ry:rx,am=swap?rawy:rawx,b=swap?rx:ry,bm=swap?rawx:rawy;
         if(a<0)a=0;if(a>am)a=am;if(b<0)b=0;if(b>bm)b=bm;if(flipu)a=am-a;if(flipv)b=bm-b;
         fr[nf].type=EV_ABS;fr[nf].code=ABS_MT_POSITION_X;fr[nf].value=(s32)(a*(ow-1)/am);nf++;
         fr[nf].type=EV_ABS;fr[nf].code=ABS_MT_POSITION_Y;fr[nf].value=(s32)(b*(oh-1)/bm);nf++;}
       got=0;}
     if(nf<127)fr[nf++]=*p; continue;}
   /* fin de trame */
   int zone=-1; if(contact&&rx>KEYX){for(int k=0;k<5;k++)if(ry>=ylo[k]&&ry<yhi[k])zone=k;}
   if(held>=0||(contact&&rx>KEYX)){
     if(!contact){ if(held>=0){emit(u,EV_KEY,kc[held],0);emit(u,EV_SYN,SYN_REPORT,0);} held=-1; }
     else if(held<0&&zone>=0){held=zone;emit(u,EV_KEY,kc[held],1);emit(u,EV_SYN,SYN_REPORT,0);}
     /* sinon : doigt dans le bandeau hors zone, ou glisse -> ignore */
   } else {
     for(int k=0;k<nf;k++)emit(u,fr[k].type,fr[k].code,fr[k].value);
     emit(u,EV_SYN,SYN_REPORT,0);
   }
   nf=0;contact=0;}}
}
__attribute__((naked)) void _start(void){asm volatile("mov x0, sp\n bl start_c\n mov x8,#93\n svc 0");}
