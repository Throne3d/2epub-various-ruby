<!--(set_escape)-->
    html
<!--(end)-->
<div id="<!--(if postType=="COMMENT")-->cmt<!--(else)-->entry<!--(end)-->-@!id!@" depth="@!depth!@" data-type="@!postType!@" class="@!moiety!@">
    <div class="user">
        <div class="usericon"><!--(if imagePath!="")--><img src="@!imagePath!@" /><!--(else)--><div>X</div><!--(end)--></div>
        <div class="username"><!--(if face!="")-->@!userDisplay!@: @!face!@<!--(else)-->@!user!@<!--(end)--></div>
    </div>
    <div class="content">
        $!content!$
      <!--(if timestamp!="")-->
        <div class="timestamp">@!timestamp!@</div>
      <!--(end)-->
    </div>
</div>
