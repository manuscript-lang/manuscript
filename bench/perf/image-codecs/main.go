package main
import ("bytes";"fmt";"image";"image/color";"image/jpeg";"image/png";"time")
func main(){
 w,h:=2048,2048
 img:=image.NewRGBA(image.Rect(0,0,w,h))
 for y:=0;y<h;y++{ for x:=0;x<w;x++{
  img.SetRGBA(x,y,color.RGBA{uint8((x*3+y*5+(x*y)/512)%256),uint8((x+y*2+(x+y*3)%251)%256),uint8((x*7+y+(x/8)*(y/8))%256),255}) }}
 t:=time.Now(); var b bytes.Buffer; png.Encode(&b,img); fmt.Println("png encode",time.Since(t),b.Len())
 t=time.Now(); d,_:=png.Decode(bytes.NewReader(b.Bytes())); fmt.Println("png decode",time.Since(t),d.Bounds().Dx())
 t=time.Now(); var j bytes.Buffer; jpeg.Encode(&j,img,&jpeg.Options{Quality:75}); fmt.Println("jpeg encode",time.Since(t),j.Len())
 t=time.Now(); jd,_:=jpeg.Decode(bytes.NewReader(j.Bytes())); fmt.Println("jpeg decode",time.Since(t),jd.Bounds().Dx())
}
