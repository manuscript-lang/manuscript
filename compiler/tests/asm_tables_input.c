int h(int x);
int f(int x);
int h(int x){return x+1;}
int f(int x){
 int y=h(x);
 return y*2;
}
