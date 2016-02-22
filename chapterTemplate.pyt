<!--(set_escape)-->
    html
<!--(end)-->
<!doctype html>
<html>
    <head><meta charset="UTF-8" /><link rel='stylesheet' href='../style/default.css' type='text/css' /></head>
    <body>
     <!--(if sectionTitle!="")-->
        <h2 class="section-title">@!sectionTitle!@</h2>
      <!--(if sectionTitleExtras!="")-->
        <strong class="section-subtitle">@!sectionTitleExtras!@</strong><br />
      <!--(end)-->
     <!--(end)-->
     <h3 class="entry-title">@!chapter['postTitle']!@</h3>
     <!--(if chapter['nameExtras']!="")-->
        <strong class="entry-subtitle">(@!chapter['name']!@ @!chapter['nameExtras']!@)</strong><br />
     <!--(end)-->
     <!--(if chapter['authors']!="")-->
        <strong class="entry-authors">Authors: @!chapter['authors']!@</strong><br />
     <!--(end)-->
     <!--(for item in chapterContents)-->
      <!--(if item == "entry")-->
        $!divList["0"]!$
      <!--(elif item[:3] == "cmt")-->
        $!divList[item.split("cmt-")[1]]!$
      <!--(elif item[:10] == "branchNote")-->
       <!--(if item[10:] == "1")-->
        <div class="branchNote branchNote1">This is a branch point. Multiple story threads start here. This is the first thread.</div>
       <!--(else)-->
        <div class="branchNote branchNote@!item[10:]!@">The previous branch has ended. This is thread #@!int(item[10:])!@.</div>
       <!--(end)-->
      <!--(end)-->
     <!--(end)-->
    </body>
</html>
